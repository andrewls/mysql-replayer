# frozen_string_literal: true

module MysqlReplayer
  class PreparedStatementCache
    def initialize(db)
      @db = db
      # probably the simplest way to manage these is just by using the SQL
      # strings as keys in a big hash
      @statements = {}
      # In a twist of fate that's also super weird, we have no guarantee of
      # a prepared statement being called by the same thread that originally
      # prepared it, so we need an easy way to determine if the statement
      # we prepared is in fact a match for the statement we're trying to execute.
      # We also then need to be able to extract the arguments that were passed
      # into the query.
      #
      # We do this by turning _all_ ? in the original prepared statements into
      # capture groups that match any character with an optional spaces after
      # (in case the ? is at the end of the line). By doing this, we can extract
      # the arguments that were added in the logs.
      # Not gonna lie, it's a _brutally_ messy system, it'd be way easier
      # to just execute these without using prepared statements. Good thing
      # I'm committed to science and such.
      @regexes = {}
    end

    def prepare(sql)
      @statements[sql] ||= @db.prepare(sql)
      @regexes[sql] = Regexp.compile(
        Regexp.escape(
          sql.gsub(/\s+/, ' ')
        ).gsub('\ \?', '\ (.+)').gsub('\ ', '\s+')
      )
    end

    def execute(sql, metrics)
      # This one is trickier. We first have to find if we have a prepared
      # statement that matches it.
      found = false
      prepared_statement, match = @statements.keys.each do |prepared|
        if (match = @regexes[prepared].match(sql)).present?
          found = true
          break [prepared, match]
        end
      end

      # If we found a prepared statement that matches, execute it using
      # all the captured data
      if found && match
        metrics[:executed_as_query] = false
        @statements[prepared_statement].execute(*match.captures.map { |s| s.gsub!(/\A["']|["']\z/, '') })
      else
        # Fall back to just querying on the db.
        metrics[:executed_as_query] = true
        @db.query(sql)
      end
    end
  end
end
