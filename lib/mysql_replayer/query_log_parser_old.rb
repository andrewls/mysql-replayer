# frozen_string_literal: true

require_relative 'query_log_entry'
require_relative 'buffer'
require 'colorize'
require 'json'

LINE_START_REGEX = /^(?<timestamp>\d{4}\-\d{2}\-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z)\s+(?<hi_res_timestamp>\d{4}\-\d{2}\-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z)\s+(?<thread_id>\d+)\s+(?<command>[a-zA-Z]+)\s+(?<argument>.*)$/
CONFLICT_RESOLUTION_REGEX = /^(?<timestamp>\d{4}\-\d{2}\-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z)\s+(?<remainder>.*)$/

module MysqlReplayer
  # This class is responsible for parsing each log line out of the query logs
  # and returning it in useable pieces to the caller.
  class QueryLogParser
    def initialize(file)
      @file = file
      @buffer = Buffer.new(size: 10)
      @changes = []
    end

    def write_changes
      if @changes.count > 0
        File.open("changes/#{@file.split('/').last}.changes.txt", 'w') do |f|
          f.write JSON.pretty_generate(@changes)
        end
      end
    end

    def resolve_conflict(line, line_number)
      timestamp = line.timestamp
      remainder = line.argument
      puts "Lines #{line.start_line} to #{line_number} of file #{@file} has a conflict that must be resolved".yellow

      puts "The 10 lines previous to this are:".yellow
      @buffer.values.each_with_index do |value, index|
        output_string = "#{10 - index}: #{value.format_for_conflict_resolution}\n"
        puts timestamp.present? && value.timestamp == timestamp ? output_string.green : output_string.red
      end
      puts "The contents of the line are #{line.timestamp} #{line.argument}".cyan

      user_choice = nil
      while ![1, 2, 3].include?(user_choice)
        puts "What would you like to do with this line?".cyan
        puts "1. Merge it with a previous line"
        puts "2. Delete it"
        puts "3. Edit it"
        # user_choice = STDIN.gets.chomp.to_i
        user_choice = 2 # After inspecting, we're just always gonna delete them.
        # It makes _way_ more sense, it lets us groom the logs way faster, and
        # I went through more than 30 files and all but 2 log entries needed to
        # be deleted. Those two were edited, and were selects that are also
        # easily ignored and statistically insignificant in the face of the
        # sheer volume of all the logs that we have.
      end
      case user_choice
      when 1
        # In this case, the user selected yes, so we ask which line to merge.
        puts "Which line should this line be merged with? (1-10) ".cyan
        index = STDIN.gets.chomp.to_i
        @changes << {
          line_number: line.start_line,
          original_end_line: line_number,
          original_text: line.format_for_conflicting_line,
          timestamp: timestamp,
          remainder: remainder,
          previous_line: @buffer.values[index].format_for_conflict_resolution,
          offset: 10 - index,
          proposed_action: :merge,
          proposed_fix: @buffer.values[index].format_for_conflict_resolution + remainder
        }
      when 2
        puts "This line will be deleted".cyan
        @changes << {
          line_number: line.start_line,
          original_end_line: line_number,
          original_text: line.format_for_conflicting_line,
          timestamp: timestamp,
          remainder: remainder,
          proposed_action: :delete
        }
      when 3
        # In this case, we print the line for the user to edit and ask them to make changes.
        puts "This line will now be opened in ViM for editing".cyan
        File.open('tmp.txt', 'w') { |f| f.write line.format_for_conflicting_line }
        system('vim tmp.txt')
        user_input = File.read('tmp.txt')
        File.delete('tmp.txt')
        puts "The user put in #{user_input}"
        @changes << {
          line_number: line.start_line,
          original_end_line: line_number,
          original_text: line.format_for_conflicting_line,
          timestamp: timestamp,
          remainder: remainder,
          proposed_action: :edit,
          new_text: user_input
        }
      end
    end

    def parse(&block)
      # get each row and then call block.call to send the parsed log line back.
      current_match = nil
      line_number = 0
      error_for_resolution = nil
      File.foreach(@file) do |line|
        line_number += 1
         if line.start_with?('2021')
          if (match = LINE_START_REGEX.match(line)).present?
            if error_for_resolution.present?
              self.resolve_conflict(error_for_resolution, line_number)
              # Since it's an error we don't have to push it onto the buffer
              # Instead, we just arrange to skip to the next log entry
              # in the queue
              previous = nil
              error_for_resolution = nil
            else
              previous = @buffer << current_match
            end
            yield previous if previous
            current_match = QueryLogEntry.new(
              timestamp: match[:timestamp],
              hi_res_timestamp: match[:hi_res_timestamp],
              thread_id: match[:thread_id],
              command: match[:command],
              argument: (+'' << match[:argument])
            )
            current_match.start_line = line_number
          elsif (match = CONFLICT_RESOLUTION_REGEX.match(line)).present?
            # In this case we definitely have a problem that we'll need to
            # resolve before we can continue.
            CONFLICT_RESOLUTION_REGEX.match(line)
            current_match = QueryLogEntry.new(
              timestamp: match[:timestamp],
              argument: match[:remainder]
            )
            current_match.start_line = line_number
            error_for_resolution = current_match
          else
            raise "Ran into a case that doesn\'t match the fallback regex! #{line}"
          end
        else
          current_match.argument << line
        end
      end
    end

    class << self
      def parse(log_file, &block)
        parser = self.new(log_file)
        parser.parse(&block)
        parser.write_changes
      end
    end
  end
end
