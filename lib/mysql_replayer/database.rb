# frozen_string_literal: true

require 'mysql2'

module MysqlReplayer
  class Database
    def initialize(url:)
      @url = url
      @mutex = Mutex.new
      # Attempt a db connection to make sure it works
      if (match = MYSQL_URL_REGEX.match(@url)).present?
        @host = match[:host]
        @port = match[:port]
        @username = match[:username]
        @password = match[:password]
        @database = match[:database]
        puts "Mysql Data: #{@host} #{@username} #{@password} #{@port} #{@database}"
        client = self.connection
        # If we haven't thrown an exception yet, we're good.
        client.close
        @connections = nil
      else
        raise "Invalid database url! #{@url}"
      end
    end

    def clean_up
      if @connections
        @connections.values.map(&:close)
      end
    end

    def connection
      @mutex.synchronize do
        @connections ||= Hash.new do |h, k|
          h[k] = client = Mysql2::Client.new(
            host: @host,
            port: @port.to_i,
            username: @username,
            password: @password,
            database: @database
          )
        end

        @connections[Thread.current.object_id]
      end
    end
  end
end
