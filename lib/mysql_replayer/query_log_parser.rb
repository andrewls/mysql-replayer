# frozen_string_literal: true
require_relative 'query_log_entry'
require 'active_support/core_ext/object/blank'
require 'fast_blank'


LINE_REGEX = /^(?<timestamp>\d{4}\-\d{2}\-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z)\s+(?<hi_res_timestamp>\d{4}\-\d{2}\-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z)\s+(?<thread_id>\d+)\s+(?<command>[a-zA-Z]+)\s+(?<argument>.*)$/

module MysqlReplayer
  class QueryLogParser
    def initialize(file)
      @file = file
    end

    def parse
      File.foreach(@file) do |line|
        raise 'Must use a block!' unless block_given?
        if (match = LINE_REGEX.match(line)).present?
          entry = QueryLogEntry.new(
            timestamp: Time.iso8601(match[:timestamp]),
            hi_res_timestamp: Time.iso8601(match[:hi_res_timestamp]),
            thread_id: match[:thread_id],
            command: match[:command],
            argument: match[:argument]
          )
          if entry.complete?
            yield entry
          else
            STDERR.puts "Line is not complete: #{entry.inspect}"
          end
        else
          # raise "Line did not match! #{line}"
          STDERR.puts "Line did not match! #{line}"
        end
      end
    end

    class << self
      def parse(file)
        raise 'Must provide a parse block!' unless block_given?
        self.new(file).parse do |row|
          yield row
        end
      end
    end
  end
end
