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
          }
        ].freeze
      end
    end
  end
end
