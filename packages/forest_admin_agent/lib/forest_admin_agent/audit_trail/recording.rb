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

      # Auditing must never take the request down with it. By the time a change is recorded the write has
      # already happened, so raising would report a failure for an operation that succeeded (and invite a
      # retry that duplicates it); a snapshot read failing must not block the write either. Losing the row
      # is the lesser evil, so it is logged and dropped.
      def audit_safely
        yield
      rescue StandardError => e
        Facades::Container.logger.log('Error', "[ForestAdmin] Audit trail unavailable, skipping: #{e.message}")
        nil
      end
    end
  end
end
