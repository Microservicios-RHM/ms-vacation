require 'json'
require_relative 'envelope'

module Infrastructure
  module Messaging
    class Consumer
      def initialize(connection:, exchange_name:, queue_name:, logger:)
        @connection = connection
        @exchange_name = exchange_name
        @queue_name = queue_name
        @logger = logger
        @handlers = {}
      end

      # Acepta un objeto invocable (con #call) o un bloque.
      def on(routing_key, handler = nil, &block)
        @handlers[routing_key] = handler || block
      end

      def start
        channel = @connection.create_channel
        channel.prefetch(10)
        exchange = channel.topic(@exchange_name, durable: true)
        queue = channel.queue(@queue_name, durable: true)
        @handlers.each_key { |routing_key| queue.bind(exchange, routing_key: routing_key) }

        queue.subscribe(manual_ack: true, block: false) do |delivery_info, _properties, body|
          dispatch(channel, delivery_info, body)
        end

        @logger.info(
          'RabbitMQ connection ready',
          exchange: @exchange_name, queue: @queue_name, bindings: @handlers.keys
        )
      end

      # route contiene la lógica pura (parseo + despacho), separada de dispatch/ack para poder
      # probarla sin una conexión real — ver consumer_spec.rb.
      def route(routing_key, body)
        handler = @handlers[routing_key]
        return unless handler

        begin
          parsed = JSON.parse(body)
        rescue JSON::ParserError => e
          raise "evento malformado: #{e.message}"
        end

        handler.call(Envelope.parse(parsed))
      end

      private

      def dispatch(channel, delivery_info, body)
        route(delivery_info.routing_key, body)
        channel.ack(delivery_info.delivery_tag)
      rescue StandardError => e
        @logger.error('event discarded', routingKey: delivery_info.routing_key, error: e.message)
        channel.nack(delivery_info.delivery_tag, false, false)
      end
    end
  end
end
