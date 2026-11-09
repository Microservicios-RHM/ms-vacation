require 'opentelemetry/sdk'
require 'opentelemetry/exporter/zipkin'
require 'opentelemetry/instrumentation/rack'
require 'opentelemetry/instrumentation/sinatra'
require 'opentelemetry/instrumentation/pg'

module Infrastructure
  module Observability
    # Arranque de OpenTelemetry (Reto 8):
    #   - service.name: OTEL_SERVICE_NAME (vacaciones-service).
    #   - Exportador: Zipkin hacia OTEL_EXPORTER_ZIPKIN_ENDPOINT (nombre de red Docker `zipkin`).
    #   - Propagación: W3C Trace Context + Baggage (OTEL_PROPAGATORS=tracecontext,baggage), el
    #     mismo estándar que usan los servicios en Node, Python, Go y PHP.
    #   - Automático: spans de entrada de Sinatra/Rack y consultas a PostgreSQL (pg).
    #   - Manual: publicación/consumo en RabbitMQ (MessageTracing) y el span raíz del scheduler
    #     (TransitionTracing), que no nace de ninguna petición HTTP.
    #
    # Sin OTEL_EXPORTER_ZIPKIN_ENDPOINT (pruebas, ejecución local sin Zipkin) no se configura el
    # SDK: la API queda en modo no-op y los spans no se registran.
    module Tracing
      UNTRACED_ENDPOINTS = ['/health', '/metrics'].freeze

      def self.configure!
        endpoint = zipkin_base_url(ENV.fetch('OTEL_EXPORTER_ZIPKIN_ENDPOINT', ''))
        return false if endpoint.empty?

        # El exportador agrega /api/v2/spans solo si la URL recibida es idéntica a la variable de
        # entorno; con otra URL la usa tal cual. Se deja la variable con la URL base (solo en este
        # proceso) para que construya http://zipkin:9411/api/v2/spans una sola vez.
        ENV['OTEL_EXPORTER_ZIPKIN_ENDPOINT'] = endpoint

        OpenTelemetry::SDK.configure do |config|
          config.service_name = ENV.fetch('OTEL_SERVICE_NAME', 'vacaciones-service')
          config.add_span_processor(
            OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
              OpenTelemetry::Exporter::Zipkin::Exporter.new(endpoint: endpoint)
            )
          )
          # El healthcheck de Docker y el scraping de Prometheus taparían en Zipkin las trazas
          # de negocio.
          config.use 'OpenTelemetry::Instrumentation::Rack', untraced_endpoints: UNTRACED_ENDPOINTS
          config.use 'OpenTelemetry::Instrumentation::Sinatra'
          config.use 'OpenTelemetry::Instrumentation::PG'
        end
        true
      end

      # A diferencia de los SDK de Node, Python, Go y PHP, el exportador Zipkin de Ruby agrega
      # /api/v2/spans por su cuenta a OTEL_EXPORTER_ZIPKIN_ENDPOINT: con la URL completa (la misma
      # variable de todo el ecosistema) publicaría en /api/v2/spans/api/v2/spans (404 de Zipkin).
      def self.zipkin_base_url(endpoint)
        endpoint.sub(%r{/api/v2/spans/?\z}, '')
      end
    end
  end
end
