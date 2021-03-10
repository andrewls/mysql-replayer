# frozen_string_literal: true
require 'active_support/core_ext/integer/time'
require 'mysql2'
require 'json'
require 'oj'
require_relative 'database'
require_relative 'query_log_parser'
require_relative 'prepared_statement_cache'

Thread.abort_on_exception = true

MYSQL_URL_REGEX = /(?<scheme>\w+):\/\/(?<username>[a-zA-Z]+):(?<password>\w+)@(?<host>[a-zA-Z0-9\.\-]+):(?<port>\d+)\/(?<database>[a-zA-Z_]+)/

# Constraints on how queries can be run
# In pre-run mode, we just run all update operations in parallel

module MysqlReplayer
  # This class is responsible for the overarching logic of actually replaying
  # a database log file.
  PRE_PEAK = 0
  PEAK = 1
  POST_PEAK = 2
  MUTATING_OPERATIONS = %w[prepare create call update insert delete].to_set.freeze
  MYSQL_THREADS = 50

  class Executor
    def initialize(file:, database_url:, start_time: Time.at(0), end_time:Time.current)
      @file = file
      @database_url = database_url
      @start_time = start_time
      @end_time = end_time
      @phase = PRE_PEAK
      @threads = []
      @db_mutex = Mutex.new
      @general_queue = Queue.new
      @logger_queue = Queue.new
      MYSQL_THREADS.times do
        # These threads will go ahead and process all the select queries. In
        # this way we can be pretty confident that we won't run into problems
        # with inoptimal parallelism. Each of the threads can run all their
        # own weird one-off stuff and the selects can be split evenly among
        # the first thread to get to them.
        @threads << Thread.new do
          db = self.database.connection
          # Ensure that the db client is connected early
          db.query('SELECT 1')
          while (entry = @general_queue.pop).present?
            self.process_query_from_entry(entry, db)
          end
        end
      end

      # also initialize the logger that's actually going to write all our
      # query results out to disc
      @threads << Thread.new do
        total_queries_run = 0
        errors = 0
        File.open('query-metrics.txt', 'w') do |logs|
          while (metric = @logger_queue.pop).present?
            total_queries_run += 1
            errors += 1 if metric[:is_error]
            print "\rTotal Queries Run: #{total_queries_run}\t\tErrors: #{errors}\t\tCurrent latency: #{metric[:query_queue_latency]} seconds\t\tCurrent timestamp: #{metric[:entry_timestamp].iso8601}\t\t\t"
            # Now we just need to write out to the results file
            logs.write(Oj.dump(metric))
            logs.write("\n")
          end
        end
      end
    end

    def database
      @db_mutex.synchronize do
        @database ||= Database.new(url: @database_url)
      end
    end

    def process_query_from_entry(entry, db)
      # Determine how far behind we are
      elapsed = Time.current - @current_phase_started_at
      expected = entry.hi_res_timestamp - @current_phase_first_timestamp
      metrics = {
        entry_timestamp: entry.timestamp,
        query_queue_latency: elapsed - expected,
        operation: entry.command,
        query: entry.argument,
      }
      query_start_time = Time.current
      begin
        # This is now our biggest wildcard.
        # If this is a prepared statement then we need to
        # go ahead and run it as such.
        #
        # If it's an execution of a previously prepared statement then
        # we need to search through our existing prepared statements and
        # ensure that we have a correct one. If so, we execute it.
        #
        # We should not execute more than one copy of a prepared statement
        # per connection, which we'll need to watch for due to the problem
        # we have with reconnecting.
        #
        # Anything that's left at the end of all this can be happily executed
        # using `query`
        case entry.command
        when 'Prepare' then Thread.current[:prepared_statement_cache].prepare(entry.argument)
        when 'Execute' then Thread.current[:prepared_statement_cache].execute(entry.argument, metrics)
        else result = db.query(entry.argument)
        end
      rescue Mysql2::Error => e
        metrics[:is_error] = true
        metrics[:error] = e.message
      end
      query_end_time = Time.current
      metrics[:execution_time] = query_end_time - query_start_time
      @logger_queue << metrics
    end

    def spawn_new_thread(mysql_id)
      queue = Queue.new
      # Spawn the thread that will actually do the work
      @threads << Thread.new do
        db = self.database.connection
        # fail early if there's a DB connection problem
        db.query('SELECT 1')
        # These are also the threads that will run all the inserts and
        # updates that use prepared statements. As such, they need to implement
        # a prepared statement cache.
        Thread.current[:prepared_statement_cache] = PreparedStatementCache.new(db)

        # And now we start listening for things to run
        while (next_entry = queue.pop).present?
          self.process_query_from_entry(next_entry, db)
        end
      end
      # Now return the queue so work can be given to this thread by
      # other methods
      queue
    end

    def queue_for_thread(thread_id)
      @queues ||= Hash.new { |h, k| h[k] = self.spawn_new_thread(thread_id) }
      @queues[thread_id % MYSQL_THREADS]
    end

    def execute_entry(entry)
      if entry.command == 'Query' && entry.argument.downcase.start_with?('select')
        @general_queue << entry
      else
        self.queue_for_thread(entry.thread_id.to_i) << entry
      end
    end

    def handle_entry(entry)
      case @phase
      when PRE_PEAK
        # In this case we only need to worry about operations that might impact
        # the database state.
        # These are CREATE, CALL, UPDATE, INSERT, and DELETE
        operation = entry.argument.split.first.downcase
        if MUTATING_OPERATIONS.include?(operation)
          # However, we always execute the traffic _immediately_
          execute_entry(entry)
        end
      when PEAK
        # In this case, we replay the traffic _exactly_ as it occurred.
        # This means that we need to wait until we hit our relative timestamp.
        # First, find out how much time has elapsed since the start of the test
        # Then compare that to how much time should have passed according to
        # the logs. If enough time has passed, execute the query.
        elapsed = Time.current - @peak_started_at
        expected = entry.hi_res_timestamp - @peak_first_timestamp
        # If it hasn't been enough time, we wait exactly as long as the logs say
        # we need to wait.
        sleep(expected - elapsed) if (elapsed < expected)
        self.execute_entry(entry)
      when POST_PEAK
        # In this case, we've already conducted our test, we literally just
        # leave everything.
      end
    end


    def replay
      @current_phase_started_at = @replay_started_at = Time.current
      index = 0
      QueryLogParser.parse(@file) do |entry|
        index += 1
        @current_phase_first_timestamp = @replay_first_timestamp = entry.hi_res_timestamp if index == 1
        case @phase
        when PRE_PEAK then (@current_phase_started_at = @peak_started_at = Time.current) && (@current_phase_first_timestamp = @peak_first_timestamp = entry.hi_res_timestamp) && (@phase = PEAK) if entry.timestamp > @start_time
        when PEAK then @phase = POST_PEAK if entry.timestamp > @end_time
        when POST_PEAK then puts "Entered post peak phase, exiting"; return
        end
        self.handle_entry(entry)
      end
      # This queue at least we can clean up
      @logger_queue << nil
      MYSQL_THREADS.times { @general_queue << nil }
      @queues&.values&.each { |q| q << nil }
      @threads.each(&:join)
    end
  end
end
