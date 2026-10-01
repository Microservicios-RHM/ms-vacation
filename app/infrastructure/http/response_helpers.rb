require 'json'
require 'time'

module Infrastructure
  module Http
    module ResponseHelpers
      def success_body(message, data)
        { success: true, message: message, data: data }.to_json
      end

      def error_body(status, message, code, path, details: nil, conflicting_period: nil)
        error = {
          code: code,
          status: status,
          path: path,
          timestamp: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ'),
        }
        error[:details] = details if details
        error[:conflictingPeriod] = conflicting_period if conflicting_period
        { success: false, message: message, data: nil, error: error }.to_json
      end
    end
  end
end
