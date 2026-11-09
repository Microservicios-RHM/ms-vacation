require 'opentelemetry'

module Infrastructure
  module Observability
    # Propagación del contexto de traza a través de RabbitMQ (Reto 8).
    #
    # Por HTTP la propagación la hace la instrumentación de Rack, pero un mensaje AMQP no es una
    # petición HTTP: si nadie copia el `traceparent` a las cabeceras del mensaje, el consumidor
    # empieza una traza nueva. El productor crea un span PRODUCER e inyecta su contexto (W3C Trace
    # Context) en las cabeceras de Bunny; el consumidor lo extrae y procesa el evento dentro de un
    # span CONSUMER hijo.
    module MessageTracing
      module_function

      def tracer
        OpenTelemetry.tracer_provider.tracer('rhm-messaging')
      end

      # Devuelve lo que devuelva el bloque, que recibe el Hash de cabeceras a publicar.
      def with_publish_span(exchange, routing_key)
        tracer.in_span(
          "#{routing_key} publish",
          kind: :producer,
          attributes: attributes('publish', exchange, routing_key)
        ) do
          headers = {}
          OpenTelemetry.propagation.inject(headers)
          yield headers
        end
      end

      def with_consume_span(headers, queue, routing_key, &block)
        carrier = (headers || {}).each_with_object({}) { |(key, value), acc| acc[key.to_s] = value.to_s }
        parent = OpenTelemetry.propagation.extract(carrier)
        OpenTelemetry::Context.with_current(parent) do
          tracer.in_span(
            "#{routing_key} process",
            kind: :consumer,
            attributes: attributes('process', queue, routing_key),
            &block
          )
        end
      end

      def attributes(operation, destination, routing_key)
        {
          'messaging.system' => 'rabbitmq',
          'messaging.operation.type' => operation,
          'messaging.destination.name' => destination,
          'messaging.rabbitmq.destination.routing_key' => routing_key,
        }
      end
    end

    # El caso difícil del Reto 8: el scheduler dispara vacaciones.iniciadas / finalizadas sin
    # ninguna petición HTTP que cree la traza raíz. Aquí se abre ese span raíz a mano, uno por
    # período, ANTES de publicar el evento: el publish queda como hijo y su traceparent viaja a
    # auth-service (suspende la cuenta) y de ahí a notificaciones-service (envía el correo), todo
    # en una sola cascada en Zipkin. Si la transición la fuerza un POST HTTP, el span cuelga de esa
    # petición en lugar de ser raíz.
    module TransitionTracing
      SPAN_NAMES = {
        'vacaciones.iniciadas' => 'scheduler.vacaciones.iniciar',
        'vacaciones.finalizadas' => 'scheduler.vacaciones.finalizar',
      }.freeze

      def self.call(event_type, period, &block)
        OpenTelemetry.tracer_provider.tracer('rhm-scheduler').in_span(
          SPAN_NAMES.fetch(event_type, "scheduler.#{event_type}"),
          attributes: { 'vacaciones.id' => period.id.to_s, 'empleado.id' => period.empleado_id.to_s },
          &block
        )
      end
    end

    # traceId/spanId del span activo para los logs JSON: con ellos un log de Loki lleva a su traza.
    def self.trace_fields
      span_context = OpenTelemetry::Trace.current_span.context
      return {} unless span_context.valid?

      { traceId: span_context.hex_trace_id, spanId: span_context.hex_span_id }
    end
  end
end
