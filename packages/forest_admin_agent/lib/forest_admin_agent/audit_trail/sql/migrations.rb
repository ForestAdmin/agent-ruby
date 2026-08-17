module ForestAdminAgent
  module AuditTrail
    module Sql
      # The audit table's schema, as an ordered, append-only list. Nothing has shipped yet, so this is still a
      # single entry; once a release is out, never edit one — add another, since a database out there has
      # already recorded the earlier ones as applied. Every statement tolerates being replayed
      # (`if_not_exists`), which is what makes a lost race harmless.
      module Migrations
        ALL = [
          {
            name: '001-create-audit-logs',
            up: lambda do |connection, table|
              # if_not_exists: a non-PG race (no advisory lock) can let two instances both reach here.
              connection.create_table(table, if_not_exists: true) do |t|
                t.datetime :timestamp, null: false
                t.string :operation, null: false
                t.string :collection, null: false
                # Nullable, because a create's pending row has no id yet; text, because a packed composite id
                # outgrows a varchar.
                t.text :record_id
                # No default on purpose: every write sets it, so a row arriving without one is a bug worth
                # hearing about rather than a row that quietly claims to be done.
                t.string :status, null: false
                t.integer :user_id
                # Denormalised from the caller at write time: who acted then, not whoever holds that id today.
                t.text :user_first_name
                t.text :user_last_name
                t.text :user_email
                # Smart-action rows only.
                t.text :action_name
                t.string :correlation_key
                t.json :previous_values
                t.json :new_values
              end

              base = table.split('.').last
              # MySQL cannot index unbounded TEXT, so that one index needs a length prefix.
              record_id_index = { name: "#{base}_record_id", if_not_exists: true }
              record_id_index[:length] = 255 if connection.adapter_name.downcase.match?(/mysql|maria/)

              connection.add_index(table, :record_id, **record_id_index)
              connection.add_index(table, :correlation_key, name: "#{base}_correlation_key", if_not_exists: true)
              connection.add_index(table, :user_id, name: "#{base}_user_id", if_not_exists: true)
            end
          }
        ].freeze
      end
    end
  end
end
