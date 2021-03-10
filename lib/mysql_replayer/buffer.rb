# frozen_string_literal: true

require 'colorize'

LINE_SEPARATOR = ('*' * 40).yellow
PREVIOUS_LINES = ' PREVIOUS LINES '.yellow
NEXT_LINES = '   NEXT LINES   '.yellow
CURRENT_LINE = '  CURRENT LINE  '.cyan

module MysqlReplayer
  # This class exists solely for keeping track of the 10 previous lines
  # prior to any error that occurs. This way I can programmatically go through
  # the errors, making it much easier to manage a large number of errors very
  # quickly.
  class Buffer
    def initialize(size: 10)
      @size = size
      @array = []
      @has_reached_capacity = false
    end

    def <<(value)
      @array << value
      @has_reached_capacity ||= @array.size > @size
      @array.shift if @array.size > @size
    end

    def current_index
      if @has_reached_capacity
        @array.size / 2
      else
        -1
      end
    end

    def previous_lines_marker
      @previous_lines_marker ||= LINE_SEPARATOR + PREVIOUS_LINES + LINE_SEPARATOR + "\n"
    end

    def previous_lines
      index = current_index
      @array[0...index] if index >= 0
    end

    def current_value_marker
      @current_value_marker ||= LINE_SEPARATOR + CURRENT_LINE + LINE_SEPARATOR + "\n"
    end


    def next_lines_marker
      @next_lines_marker ||= LINE_SEPARATOR + NEXT_LINES + LINE_SEPARATOR + "\n"
    end

    def next_lines
      index = current_index
      @array[(index + 1)..-1] if index >= 0
    end

    def colored_lines(array, timestamp, start_index)
      colored = array.map.with_index do |line, index|
        if line.blank?
          "#{start_index + index}:"
        else
          text = line.complete? ? line.format_for_conflict_resolution : line.format_for_conflicting_line
          result = +''
          result << (start_index + index).to_s
          result << ': '
          result << (line.timestamp == timestamp ? text.green : text.red)
          result
        end
      end
      colored.join("\n")
    end

    def inspect
      current = current_value
      current_timestamp = current.timestamp
      result = +''
      result << self.previous_lines_marker
      result << self.colored_lines(self.previous_lines, current_timestamp, -5)
      result << "\n"
      result << self.current_value_marker
      result << current.format_for_conflicting_line.cyan
      result << "\n"
      result << self.next_lines_marker
      result << self.colored_lines(self.next_lines, current_timestamp, 1)
      result
    end

    def current_value
      index = current_index
      @array[index] if index >= 0
    end

    # Honestly the fact that this does not always assign probably makes it a terrible idea
    # To define this method this way, but I'm doing it anyway.
    def current_value=(v)
      index = current_index
      @array[index] = v if index >= 0
    end

    def values
      @array
    end
  end
end
