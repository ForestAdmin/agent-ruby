module ForestAdminAgent
  module AuditTrail
    # Records smart-action invocations into the same table as the field-level history.
    #
    # {Capture} cannot see them: the customizer has no `Execute` hook, and an action's writes are only
    # audited when it goes through the Forest data layer — a direct ORM write (`Customer.find(id).update!`)
    # is invisible to the agent and is therefore not recorded at all. What lands here is the invocation
    # itself: who ran which action, on which records, with which form values, and whether it raised.
    class ActionCapture
      include Recording

      EXECUTED = 'action'.freeze
      FAILED = 'action_failed'.freeze
      # Bulk runs over a select-all selection, and global actions, target no id we can name without
      # querying the whole selection: they get one row attached to no record rather than none at all.
      NO_RECORD = ''.freeze

      def initialize(store, redact = {})
        @store = store
        @redact = redact || {}
      end

      def record(caller:, collection:, action_name:, form_values:, record_ids:, failed: false)
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
              action_name: action_name,
              user_id: caller&.id,
              correlation_key: correlation_key,
              previous_values: {},
              new_values: values
            )
          )
        end
      end
    end
  end
end
