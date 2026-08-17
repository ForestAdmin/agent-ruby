require 'securerandom'
require 'time'

module ForestAdminAgent
  module AuditTrail
    # Shared by the two capture layers: {Capture} for the changes Forest writes, {ActionCapture} for the
    # smart actions it runs. Holds the write protocol's vocabulary and its failure policy.
    module Recording
      REDACTED = '[redacted]'.freeze
      # A row is inserted before the write and confirmed after it. One left PENDING means the write may or
      # may not have landed — that residue is evidence, and it is the point.
      PENDING = 'pending'.freeze
      DONE = 'done'.freeze

      IDENTITY = { user_id: :id, user_first_name: :first_name,
                   user_last_name: :last_name, user_email: :email }.freeze

      # Denormalised at write time, so the row says who acted then rather than whoever holds that id today.
      # Read defensively: a caller built by another code path need not carry a full identity, and a
      # NoMethodError here would refuse the write outright under `critical: true`.
      def identity_of(caller)
        IDENTITY.transform_values { |reader| caller.respond_to?(reader) ? caller.public_send(reader) : nil }
      end

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

      # Everything after the pending insert is best-effort: by then the write has happened, so raising would
      # report a failure for an operation that succeeded (and invite a retry that duplicates it). Losing the
      # row is the lesser evil, so it is logged and dropped. Only the pending insert itself can refuse an
      # operation, and only under `critical: true` — see {AuditTrail.critical?}.
      def audit_safely
        yield
      rescue StandardError => e
        AuditTrail.log_failure(e)
        nil
      end
    end
  end
end
