# frozen_string_literal: true

module MysqlReplayer
  # This class is responsible for serving as a container for log entries.
  class QueryLogEntry
    attr_accessor :timestamp, :hi_res_timestamp, :thread_id, :command, :argument, :start_line
    def initialize(timestamp:, hi_res_timestamp: nil, thread_id: nil, command: nil, argument:)
      @timestamp = timestamp
      @hi_res_timestamp = hi_res_timestamp
      @thread_id = thread_id
      @command = command
      @argument = argument
    end

    def format_for_conflict_resolution
      "#{@timestamp}\t#{@hi_res_timestamp}\t#{@thread_id}\t#{@command}\t#{@argument}"
    end

    def format_for_conflicting_line
      "#{@timestamp} #{@argument}"
    end

    def complete?
      @timestamp.present? && @hi_res_timestamp.present? && @thread_id.present? && @command.present? && (@argument.present? || @command == 'Quit')
    end
  end
end
