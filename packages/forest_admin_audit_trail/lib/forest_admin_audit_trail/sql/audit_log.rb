module ForestAdminAuditTrail
  module Sql
    # ActiveRecord model for the audit table. Its table name (and schema) is assigned at runtime by
    # the SqlStore once the connection and migrations are ready. The JSON attribute overrides force
    # Hash <-> JSON casting on every adapter (Postgres json, or text on SQLite).
    class AuditLog < AuditConnectionBase
      attribute :previous_values, :json
      attribute :new_values, :json
    end
  end
end
