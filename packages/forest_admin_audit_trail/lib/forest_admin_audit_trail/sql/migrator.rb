module ForestAdminAuditTrail
  module Sql
    # Creates and evolves the audit table through an ordered, append-only list of migrations, tracked
    # in a dedicated `audit_migrations` table (namespaced in the `forest` schema on Postgres).
    #
    # On Postgres the migrations run inside a transaction-scoped advisory lock, so several agent
    # instances booting at once apply them one after another instead of racing on the same DDL. The
    # schema is created (and committed) first, made idempotent (CREATE SCHEMA IF NOT EXISTS +
    # tolerating a concurrent create), because the lock cannot cover a not-yet-existing schema.
    class Migrator
      MIGRATIONS_TABLE = 'audit_migrations'.freeze
      # Arbitrary but stable key pair identifying the audit-trail migration critical section.
      ADVISORY_LOCK = [0x464f, 0x5254].freeze # "FO", "RT"

      MIGRATIONS = [
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

      def initialize(connection, schema:, table_name:)
        @connection = connection
        @schema = schema # nil on adapters without schema support
        @table_name = table_name
      end

      def run
        ensure_schema

        if postgres?
          @connection.transaction do
            @connection.execute("SELECT pg_advisory_xact_lock(#{ADVISORY_LOCK[0]}, #{ADVISORY_LOCK[1]})")
            apply_pending
          end
        else
          apply_pending
        end
      end

      private

      def postgres?
        @connection.adapter_name.downcase.include?('postgres')
      end

      def schema?
        postgres? && @schema.present?
      end

      def qualified(name)
        schema? ? "#{@schema}.#{name}" : name
      end

      # Create the schema first and commit it: the migrations open DDL on the same connection, and a
      # CREATE SCHEMA still pending in the lock transaction would not be visible to them.
      def ensure_schema
        return unless schema?

        @connection.execute("CREATE SCHEMA IF NOT EXISTS #{@connection.quote_schema_name(@schema)}")
      rescue ActiveRecord::StatementInvalid => e
        # Another instance created it concurrently — CREATE SCHEMA is not fully race-free.
        raise unless /already exists|duplicate/i.match?(e.message)
      end

      def apply_pending
        done = applied_migrations
        table = qualified(@table_name)

        MIGRATIONS.each do |migration|
          next if done.include?(migration[:name])

          migration[:up].call(@connection, table)
          @connection.execute(
            "INSERT INTO #{@connection.quote_table_name(migrations_table)} (name) " \
            "VALUES (#{@connection.quote(migration[:name])})"
          )
        end
      end

      def applied_migrations
        ensure_migrations_table

        @connection.select_values("SELECT name FROM #{@connection.quote_table_name(migrations_table)}")
      end

      def ensure_migrations_table
        @connection.create_table(migrations_table, id: false, if_not_exists: true) do |t|
          t.string :name, null: false
        end
      end

      def migrations_table
        qualified(MIGRATIONS_TABLE)
      end
    end
  end
end
