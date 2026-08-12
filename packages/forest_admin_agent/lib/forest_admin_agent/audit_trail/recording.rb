require 'securerandom'
require 'time'

module ForestAdminAgent
  module AuditTrail
    # Shared by the two capture layers: {Capture} for the changes Forest writes, {ActionCapture} for the
    # smart actions it runs.
    module Recording
      REDACTED = '[redacted]'.freeze

      # Same id for every change made within one request — set on the caller by the agent (see
      # CallerParser), mirroring the Node agent's caller.requestId.
      def correlation_key_for(caller)
        (caller.respond_to?(:request_id) && caller.request_id) || SecureRandom.uuid
      end

      def redact(values, redacted_fields)
        return values if redacted_fields.empty?

        values.each_with_object({}) do |(field, value), result|
          result[field] = redacted_fields.include?(field) ? REDACTED : value
        end
      end

      def now
        Time.now.utc.iso8601(3)
      end
    end
  end
end
