require 'dotenv'

module Infrastructure
  Settings = Struct.new(
    :port, :log_level,
    :db_host, :db_port, :db_name, :db_user, :db_password, :db_pool_max,
    :db_connect_max_attempts, :db_connect_retry_delay_ms,
    :broker_url, :broker_exchange, :broker_queue,
    :broker_connect_max_attempts, :broker_connect_retry_delay_ms,
    keyword_init: true
  ) do
    def database_url
      "postgres://#{db_user}:#{db_password}@#{db_host}:#{db_port}/#{db_name}"
    end
  end

  class ConfigError < StandardError; end

  module Config
    REQUIRED = %w[DB_HOST DB_NAME DB_USER DB_PASSWORD BROKER_URL].freeze

    def self.load
      Dotenv.load if File.exist?('.env')

      missing = REQUIRED.reject { |key| ENV[key] && !ENV[key].empty? }
      raise ConfigError, "Configuración inválida o incompleta: #{missing.join(', ')}" unless missing.empty?

      broker_url = ENV.fetch('BROKER_URL')
      unless broker_url.start_with?('amqp://', 'amqps://')
        raise ConfigError, 'BROKER_URL debe ser una URL amqp:// o amqps://'
      end

      Settings.new(
        port: env_int('PORT', 8080),
        log_level: ENV.fetch('LOG_LEVEL', 'info'),

        db_host: ENV.fetch('DB_HOST'),
        db_port: env_int('DB_PORT', 5432),
        db_name: ENV.fetch('DB_NAME'),
        db_user: ENV.fetch('DB_USER'),
        db_password: ENV.fetch('DB_PASSWORD'),
        db_pool_max: env_int('DB_POOL_MAX', 5),
        db_connect_max_attempts: env_int('DB_CONNECT_MAX_ATTEMPTS', 5),
        db_connect_retry_delay_ms: env_int('DB_CONNECT_RETRY_DELAY_MS', 1000),

        broker_url: broker_url,
        broker_exchange: ENV.fetch('BROKER_EXCHANGE', 'rhm.events'),
        broker_queue: ENV.fetch('BROKER_QUEUE', 'vacaciones.queue'),
        broker_connect_max_attempts: env_int('BROKER_CONNECT_MAX_ATTEMPTS', 5),
        broker_connect_retry_delay_ms: env_int('BROKER_CONNECT_RETRY_DELAY_MS', 1000)
      )
    end

    def self.env_int(key, fallback)
      value = ENV[key]
      return fallback if value.nil? || value.empty?

      Integer(value)
    rescue ArgumentError
      fallback
    end
  end
end
