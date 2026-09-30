require 'json'
require 'securerandom'
require 'time'

module Infrastructure
  module Messaging
    # A diferencia del Consumer (dependencia dura), Publisher nunca lanza: un fallo al publicar
    # vacaciones.programadas no debe revertir ni bloquear la respuesta HTTP de POST /vacaciones,
    # que ya persistió el período exitosamente — mismo contrato que EventPublisher en
    # ms-employees.
    class Publisher
      def initialize(connection:, exchange_name:, producer_name:, logger:)
        @connection = connection
        @exchange_name = exchange_name
        @producer_name = producer_name
        @logger = logger
        @exchange = nil
      end

      def publish(type:, data:)
        envelope = {
          id: SecureRandom.uuid,
          type: type,
          version: 1,
          occurredAt: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ'),
          producer: @producer_name,
          data: data,
        }

        ensure_exchange!
        @exchange.publish(
          JSON.generate(envelope),
          routing_key: type,
          persistent: true,
          content_type: 'application/json',
          message_id: envelope[:id]
        )
        @logger.info('Event published', eventType: type, eventId: envelope[:id])
      rescue StandardError => e
        @logger.error('Event publish failed', eventType: type, error: e.message)
      end

      private

      def ensure_exchange!
        return if @exchange

        channel = @connection.create_channel
        @exchange = channel.topic(@exchange_name, durable: true)
      end
    end
  end
end
