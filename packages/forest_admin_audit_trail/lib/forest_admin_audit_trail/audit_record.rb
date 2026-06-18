module ForestAdminAuditTrail
  # Plain value object describing one audited change. Mirrors the columns of `forest.audit_logs`.
  #
  # Only the actor's `user_id` is stored; the rest of the actor identity is correlated elsewhere
  # through `correlation_key`.
  class AuditRecord
    OPERATIONS = %w[create update delete].freeze

    attr_reader :timestamp, :operation, :collection, :record_id, :user_id, :correlation_key,
                :previous_values, :new_values

    def initialize(
      operation:,
      collection:,
      record_id:,
      previous_values:,
      new_values:,
      timestamp: nil,
      user_id: nil,
      correlation_key: nil
    )
      @timestamp = timestamp
      @operation = operation
      @collection = collection
      @record_id = record_id
      @user_id = user_id
      @correlation_key = correlation_key
      @previous_values = previous_values || {}
      @new_values = new_values || {}
    end

    def to_h
      {
        timestamp: @timestamp,
        operation: @operation,
        collection: @collection,
        record_id: @record_id,
        user_id: @user_id,
        correlation_key: @correlation_key,
        previous_values: @previous_values,
        new_values: @new_values
      }
    end
  end
end
