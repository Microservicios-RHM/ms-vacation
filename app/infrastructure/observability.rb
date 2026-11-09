require 'monitor'
require 'opentelemetry-api'

module Infrastructure
  module Observability
    SERVICE = 'vacaciones-service'
    @lock = Monitor.new
    @requests = Hash.new(0)
    @durations = Hash.new(0.0)
    @events = Hash.new(0)

    class << self
      def configure_tracing
        require 'opentelemetry/sdk'
        require 'opentelemetry/exporter/otlp'
        require 'opentelemetry/instrumentation/all'
        OpenTelemetry::SDK.configure do |config|
          config.service_name = SERVICE
          config.use_all
        end
      end

      def observe_http(method, status, duration)
        @lock.synchronize { @requests[[method, status.to_s]] += 1; @durations[method] += duration }
      end

      def observe_event(type, outcome)
        @lock.synchronize { @events[[type, outcome]] += 1 }
      end

      def metrics
        @lock.synchronize do
          lines = ['# HELP rhm_service_info Static service identity metric', '# TYPE rhm_service_info gauge', %(rhm_service_info{service="#{SERVICE}"} 1), '# HELP rhm_http_requests_total HTTP requests by method and status', '# TYPE rhm_http_requests_total counter']
          @requests.sort.each { |(method, status), value| lines << %(rhm_http_requests_total{service="#{SERVICE}",method="#{method}",status="#{status}"} #{value}) }
          lines.concat(['# HELP rhm_http_request_duration_seconds_sum Cumulative HTTP request duration', '# TYPE rhm_http_request_duration_seconds_sum counter'])
          @durations.sort.each { |method, value| lines << %(rhm_http_request_duration_seconds_sum{service="#{SERVICE}",method="#{method}"} #{value}) }
          lines.concat(['# HELP rhm_events_total Events handled by outcome', '# TYPE rhm_events_total counter'])
          @events.sort.each { |(type, outcome), value| lines << %(rhm_events_total{service="#{SERVICE}",event_type="#{type}",outcome="#{outcome}"} #{value}) }
          lines.join("\n") + "\n"
        end
      end
    end
  end
end
