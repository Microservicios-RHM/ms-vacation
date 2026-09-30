require 'pg'
require 'connection_pool'

module Infrastructure
  module Persistence
    module Database
      def self.connect(settings, logger)
        last_error = nil
        (1..settings.db_connect_max_attempts).each do |attempt|
          test_connection = PG.connect(settings.database_url)
          test_connection.close
          return ConnectionPool.new(size: settings.db_pool_max, timeout: 5) do
            PG.connect(settings.database_url)
          end
        rescue PG::Error => e
          last_error = e
          logger.warn('PostgreSQL connection attempt failed', attempt: attempt, error: e.message)
          if attempt < settings.db_connect_max_attempts
            sleep(settings.db_connect_retry_delay_ms / 1000.0 * attempt)
          end
        end
        raise "No fue posible conectar a PostgreSQL: #{last_error&.message}"
      end
    end
  end
end
