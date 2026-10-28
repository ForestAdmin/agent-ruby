module ForestAdminAgent
  module AuditTrail
    module Sql
      # The audit table's schema, as an ordered, append-only list. Never edit a released entry — add another,
      # since a database out there has already recorded the earlier ones as applied. Every statement tolerates
      # being replayed (`if_not_exists` / `if_exists`), which is what makes a lost race harmless.
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
                # Dropped by 002.
                t.text :previous_record_id
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
          },
          {
            # The agent no longer follows a record across a primary-key move, so nothing writes or reads the
            # column. No released version wrote it to a row a client relies on.
            name: '002-drop-previous-record-id',
            up: lambda do |connection, table|
              # Checked first as well: older ActiveRecord versions accept `if_exists` here but ignore it.
              next unless connection.column_exists?(table, :previous_record_id)

              connection.remove_column(table, :previous_record_id, if_exists: true)
            end
          },
          {
            # The timeline pages the whole table in (timestamp, id) order, which no other index serves.
            name: '003-index-timestamp-id',
            up: lambda do |connection, table|
              connection.add_index(table, %i[timestamp id], name: "#{table.split(".").last}_timestamp_id",
                                                            if_not_exists: true)
            end
          },
          {
            # A record's history is read by (collection, record_id) in (timestamp, id) order. With only
            # `record_id` and `(timestamp, id)` to choose from, Postgres either reads every row the id holds
            # across all collections, or walks the whole table's (timestamp, id) index under a LIMIT: the life
            # boundary lookup discarded 2.1M rows (486 ms) on a 2.1M-row table for a record created long ago.
            name: '004-index-record-history',
            up: lambda do |connection, table|
              base = table.split('.').last
              columns = %i[collection record_id timestamp id]
              options = { if_not_exists: true }
              options[:length] = { record_id: 255 } if connection.adapter_name.downcase.match?(/mysql|maria/)

              connection.add_index(table, columns, name: "#{base}_record_history", **options)
              next unless connection.supports_partial_index?

              # The life boundary keeps a record's `create` and `delete` rows only: without this, a record
              # updated 100k times is read whole to find its one `create`.
              connection.add_index(table, columns, name: "#{base}_life_boundaries",
                                                   where: "operation IN ('create', 'delete')", **options)
            end
          }
        ].freeze
      end
    end
  end
end
