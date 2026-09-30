require 'bunny'

module Infrastructure
  module Messaging
    # Conexión compartida entre Consumer y Publisher. Es una dependencia dura: si no logra
    # conectarse tras los reintentos, el proceso no arranca — el registro local de empleados
    # válidos (poblado por el consumidor) es indispensable para la validación 4 de
    # POST /vacaciones, así que arrancar sin él dejaría el servicio en un estado peor que no
    # arrancar en absoluto (rechazaría toda alta con "empleado inexistente").
    class Connection
      def initialize(url:, max_attempts:, retry_delay_ms:, logger:)
        @url = url
        @max_attempts = max_attempts
        @retry_delay_ms = retry_delay_ms
        @logger = logger
        @connection = nil
      end

      def start!
        last_error = nil
        (1..@max_attempts).each do |attempt|
          conn = Bunny.new(@url)
          conn.start
          @connection = conn
          return self
        rescue StandardError => e
          last_error = e
          @logger.warn('RabbitMQ connection attempt failed', attempt: attempt, error: e.message)
          sleep(@retry_delay_ms / 1000.0 * attempt) if attempt < @max_attempts
        end
        raise "No fue posible conectar a RabbitMQ: #{last_error&.message}"
      end

      def create_channel
        @connection.create_channel
      end

      def close
        @connection&.close
      end
    end
  end
end
