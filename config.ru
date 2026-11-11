require_relative 'app/bootstrap'
require_relative 'app/infrastructure/observability/metrics'

# Reto 8: métricas Prometheus de todas las peticiones y GET /metrics.
use Infrastructure::Observability::Metrics::Middleware,
    metrics: Infrastructure::Observability::Metrics.new(service: ENV.fetch('OTEL_SERVICE_NAME', 'vacaciones-service'))
run Bootstrap.build
