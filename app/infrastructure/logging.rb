require 'json'
require 'time'
require_relative 'observability/message_tracing'

module Infrastructure
  # Logger JSON de una línea con los campos mínimos del Reto 8, igual que Pino (ms-employees),
  # logging_setup.py (ms-notifications) y logger.go (ms-profiles):
  #   {"timestamp":"...","level":"INFO","service":"vacaciones-service","traceId":"...","message":"..."}
  # traceId/spanId salen del span activo de OpenTelemetry: un log de Loki lleva a su traza en Zipkin.
  class Logger
    LEVELS = { 'debug' => 0, 'info' => 1, 'warn' => 2, 'error' => 3 }.freeze

    def initialize(level: 'info', service: ENV.fetch('OTEL_SERVICE_NAME', 'vacaciones-service'), io: $stdout)
      @threshold = LEVELS.fetch(level, LEVELS['info'])
      @service = service
      @io = io
    end

    def debug(msg, **fields) = log('debug', msg, fields)
    def info(msg, **fields) = log('info', msg, fields)
    def warn(msg, **fields) = log('warn', msg, fields)
    def error(msg, **fields) = log('error', msg, fields)

    private

    def log(level, msg, fields)
      return if LEVELS.fetch(level) < @threshold

      payload = {
        timestamp: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ'),
        level: level.upcase,
        service: @service,
        **Observability.trace_fields,
        message: msg,
      }.merge(fields)
      @io.puts(JSON.generate(payload))
    end
  end
end
