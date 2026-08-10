module ForestAdminAgent
  module AuditTrail
    # One audited change. Mirrors the columns of `forest.audit_logs`; only the actor's `user_id` is
    # stored, the rest of the actor identity is correlated elsewhere through `correlation_key`.
    AuditRecord = Struct.new(
      :timestamp, :operation, :collection, :record_id, :user_id, :correlation_key,
      :previous_values, :new_values,
      keyword_init: true
    )
  end
end
