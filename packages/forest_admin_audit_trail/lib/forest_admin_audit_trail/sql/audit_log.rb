module ForestAdminAuditTrail
  module Sql
    # Abstract template for the audit model. Each SqlStore builds its own concrete subclass bound to
    # its own (schema-qualified) table, so stores with different `table_name`/`schema` no longer
    # clobber a shared class. The JSON attribute overrides force Hash <-> JSON casting on every
    # adapter (Postgres json, or text on SQLite) and are inherited by every subclass.
    class AuditLog < AuditConnectionBase
      self.abstract_class = true

      attribute :previous_values, :json
      attribute :new_values, :json
    end
  end
end
