module ForestAdminAgent
  module AuditTrail
    module Sql
      # The audit table's schema, as an ordered, append-only list. Never edit an entry that has shipped:
      # add another one, since a database out there has already recorded the earlier ones as applied. Every
      # statement is written to tolerate being replayed (`if_not_exists`), because a store that predates the
      # per-table tracking key replays them once on upgrade.
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
                t.string :record_id, null: false
                t.integer :user_id
                t.string :correlation_key
                t.json :previous_values
                t.json :new_values
              end
            end
          },
          {
            name: '002-index-record-and-correlation',
            up: lambda do |connection, table|
              base = table.split('.').last
              connection.add_index(table, :record_id, name: "#{base}_record_id", if_not_exists: true)
              connection.add_index(table, :correlation_key, name: "#{base}_correlation_key", if_not_exists: true)
              connection.add_index(table, :user_id, name: "#{base}_user_id", if_not_exists: true)
            end
          },
          {
            # Denormalised from the caller at write time: who acted then, not whoever holds that id today.
            name: '003-add-user-identity',
            up: lambda do |connection, table|
              connection.add_column(table, :user_first_name, :text, if_not_exists: true)
              connection.add_column(table, :user_last_name, :text, if_not_exists: true)
              connection.add_column(table, :user_email, :text, if_not_exists: true)
            end
          },
          {
            name: '004-add-action-name',
            up: lambda do |connection, table|
              connection.add_column(table, :action_name, :text, if_not_exists: true)
            end
          },
          {
            # The default is what backfills the rows written before the pending/confirm protocol existed.
            name: '005-add-status',
            up: lambda do |connection, table|
              connection.add_column(table, :status, :string, null: false, default: 'done', if_not_exists: true)
            end
          },
          {
            # A create's pending row has no id yet, and a packed composite id outgrows a VARCHAR(255).
            name: '006-record-id-nullable-text',
            up: lambda do |connection, table|
              base = table.split('.').last
              mysql = connection.adapter_name.downcase.match?(/mysql|maria/)

              # MySQL refuses to widen an indexed column to TEXT, so the index goes first. SQLite rebuilds
              # the whole table to change a column, dropping every index 002 created along with it — which is
              # why all three are (re)created below rather than just the one dropped here.
              connection.remove_index(table, name: "#{base}_record_id", if_exists: true)
              connection.change_column(table, :record_id, :text, null: true)

              # ... and MySQL cannot index unbounded TEXT at all: that one needs a length prefix.
              record_id_index = { name: "#{base}_record_id", if_not_exists: true }
              record_id_index[:length] = 255 if mysql

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
