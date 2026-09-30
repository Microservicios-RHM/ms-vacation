require 'json'
require 'time'

module Infrastructure
  # Logger JSON de una línea, equivalente en forma a Pino (ms-employees), logging_setup.py
  # (ms-notifications) y logger.go (ms-profiles): level, time, service, msg + campos.
  class Logger
    LEVELS = { 'debug' => 0, 'info' => 1, 'warn' => 2, 'error' => 3 }.freeze

    def initialize(level: 'info', service: 'vacaciones-service', io: $stdout)
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
        level: level,
        time: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ'),
        service: @service,
        msg: msg,
      }.merge(fields)
      @io.puts(JSON.generate(payload))
    end
  end
end
