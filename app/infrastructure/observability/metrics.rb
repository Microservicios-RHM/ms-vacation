require 'prometheus/client'
require 'prometheus/client/formats/text'

module Infrastructure
  module Observability
    # Métricas en formato Prometheus (Reto 8) con prometheus-client (client_ruby oficial).
    #
    # Mismos nombres y etiquetas que en los demás servicios del ecosistema, para que el dashboard de
    # Grafana use una sola consulta por panel:
    #   - http_requests_total{method, route, status}
    #   - http_request_duration_seconds{method, route, status}   (_bucket, _sum, _count)
    #   - process_cpu_seconds_total, process_resident_memory_bytes
    #
    # client_ruby no trae métricas de proceso como los clientes de Node, Python o Go, así que se
    # leen en cada scrape: CPU del reloj de proceso y memoria residente de /proc/self/status.
    #
    # `route` es el patrón de Sinatra (/vacaciones/:id), nunca la URL con el id real (alta
    # cardinalidad).
    class Metrics
      UNMATCHED_ROUTE = 'unmatched'.freeze
      BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10].freeze
      LABELS = %i[service method route status].freeze

      attr_reader :registry

      def initialize(service:, registry: Prometheus::Client::Registry.new, status_file: '/proc/self/status')
        @service = service
        @registry = registry
        @status_file = status_file
        @requests = registry.counter(
          :http_requests_total,
          docstring: 'Total de peticiones HTTP recibidas, por método, ruta y código de respuesta',
          labels: LABELS
        )
        @duration = registry.histogram(
          :http_request_duration_seconds,
          docstring: 'Tiempo de respuesta de las peticiones HTTP en segundos',
          labels: LABELS, buckets: BUCKETS
        )
        @cpu = registry.gauge(
          :process_cpu_seconds_total, docstring: 'Tiempo de CPU consumido por el proceso en segundos', labels: [:service]
        )
        @memory = registry.gauge(
          :process_resident_memory_bytes, docstring: 'Memoria residente del proceso en bytes', labels: [:service]
        )
      end

      def observe(method:, route:, status:, seconds:)
        labels = { service: @service, method: method, route: route, status: status.to_s }
        @requests.increment(labels: labels)
        @duration.observe(seconds, labels: labels)
      end

      def render
        @cpu.set(Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID), labels: { service: @service })
        rss = resident_memory_bytes
        @memory.set(rss, labels: { service: @service }) if rss
        Prometheus::Client::Formats::Text.marshal(@registry)
      end

      def self.route_template(env)
        route = env['sinatra.route']
        return UNMATCHED_ROUTE unless route

        route.split(' ', 2).last
      end

      private

      def resident_memory_bytes
        line = File.foreach(@status_file).find { |l| l.start_with?('VmRSS:') }
        line && (line.split[1].to_i * 1024)
      rescue SystemCallError
        nil
      end

      # Middleware Rack: mide toda petición y sirve GET /metrics.
      class Middleware
        def initialize(app, metrics:)
          @app = app
          @metrics = metrics
        end

        def call(env)
          if env['PATH_INFO'] == '/metrics'
            return [200, { 'content-type' => Prometheus::Client::Formats::Text::CONTENT_TYPE }, [@metrics.render]]
          end

          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          status, headers, body = @app.call(env)
          record(env, status, started)
          [status, headers, body]
        rescue StandardError
          record(env, 500, started)
          raise
        end

        private

        def record(env, status, started)
          @metrics.observe(
            method: env['REQUEST_METHOD'], route: Metrics.route_template(env), status: status,
            seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          )
        end
      end
    end
  end
end
