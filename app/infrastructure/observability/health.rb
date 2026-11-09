require 'timeout'
require 'opentelemetry/common'

module Infrastructure
  module Observability
    # Health Check API (Reto 8): GET /health verifica de verdad la base de datos y el broker.
    #   200 {"status":"UP","service":"vacaciones-service","checks":{"database":"UP","messageBroker":"UP"}}
    #   503 {"status":"DOWN", ...}
    # Cada check tiene un tiempo límite corto: un health check lento degrada al propio servicio.
    module Health
      CHECK_TIMEOUT_SECONDS = 2

      def self.evaluate(service, checks, timeout: CHECK_TIMEOUT_SECONDS)
        results = checks.to_h { |name, check| [name.to_s, run(check, timeout) ? 'UP' : 'DOWN'] }
        status = results.values.all?('UP') ? 'UP' : 'DOWN'
        { status: status, service: service, checks: results }
      end

      # untraced: el healthcheck de Docker llega cada 10 s y su SELECT 1 llenaría Zipkin de trazas
      # sueltas que no son negocio.
      def self.run(check, timeout)
        OpenTelemetry::Common::Utilities.untraced { Timeout.timeout(timeout) { check.call } } ? true : false
      rescue StandardError, Timeout::Error
        false
      end
    end
  end
end
