module ForestAdminAgent
  module AuditTrail
    # Records smart-action invocations into the same table as the field-level history.
    #
    # {Capture} cannot see them: the customizer has no `Execute` hook, and an action's writes are only
    # audited when it goes through the Forest data layer — a direct ORM write (`Customer.find(id).update!`)
    # is invisible to the agent and is therefore not recorded at all. What lands here is the invocation
    # itself: on which records, with which form values, and whether it raised. Which action it was lives in
    # the Forest activity logs — `correlation_key` is the join.
    class ActionCapture
      include Recording

      EXECUTED = 'action'.freeze
      FAILED = 'action_failed'.freeze
      # What of the action's answer is worth keeping — an allowlist, not a denylist: a result also carries
      # the file's contents, a webhook's body and headers and arbitrary response headers. File bytes have no
      # business in an audit table and the other two routinely hold credentials, and an allowlist means a
      # field added to a result later is not stored until someone decides it should be. `html` is left out
      # too: operator-facing markup, sometimes large, and the message already says what happened.
      RESULT_FIELDS = %i[type message name mime_type method url path].freeze
      # Bulk runs over a select-all selection, and global actions, target no id we can name without
      # querying the whole selection: they get one row attached to no record rather than none at all.
      NO_RECORD = ''.freeze

      def initialize(store, redact = {})
        @store = store
        @redact = redact || {}
      end

      # No-op unless an audit database was configured, and best-effort: the action has already run.
      def record(caller:, collection:, form_values:, record_ids:, result: nil, failed: false)
        return unless @store

        audit_safely do
          timestamp = now
          correlation_key = correlation_key_for(caller)
          values = redact(form_values || {}, @redact[collection] || [])
          ids = record_ids.empty? ? [NO_RECORD] : record_ids

          ids.each do |record_id|
            @store.append(
              AuditRecord.new(
                timestamp: timestamp,
                operation: failed ? FAILED : EXECUTED,
                collection: collection,
                record_id: record_id,
                user_id: caller&.id,
                correlation_key: correlation_key,
                previous_values: values,
                new_values: summarize(result) || {}
              )
            )
          end
        end
      end

      private

      def summarize(result)
        return nil unless result.is_a?(Hash)

        result.slice(*RESULT_FIELDS).compact.transform_keys(&:to_s)
      end
    end
  end
end
