module ForestAdminAgent
  module AuditTrail
    # One audited change. Mirrors the columns of `forest.audit_logs`.
    #
    # The actor's name and email are denormalised from the caller at write time: the row says who acted then,
    # not whoever holds that user id today. `action_name` is set on smart-action rows only, and `status`
    # follows the write protocol — inserted as {Recording::PENDING} before the write and confirmed
    # {Recording::DONE} after, so a row left pending means the write may or may not have landed.
    AuditRecord = Struct.new(
      :id, :timestamp, :operation, :collection, :record_id, :previous_record_id, :status,
      :user_id, :user_first_name, :user_last_name, :user_email, :action_name,
      :correlation_key, :previous_values, :new_values,
      keyword_init: true
    )
  end
end
