module ForestAdminAgent
  module AuditTrail
    module Sql
      # Applies {Migrations::ALL} to the audit table, tracking what has run in a dedicated
      # `audit_migrations` table (namespaced in the `forest` schema on Postgres).
      #
      # On Postgres the migrations run inside a transaction-scoped advisory lock, so several agent
      # instances booting at once apply them one after another instead of racing on the same DDL. The
      # schema is created (and committed) first, made idempotent (CREATE SCHEMA IF NOT EXISTS +
      # tolerating a concurrent create), because the lock cannot cover a not-yet-existing schema.
      class Migrator
        MIGRATIONS_TABLE = 'audit_migrations'.freeze
        # Arbitrary but stable key pair identifying the audit-trail migration critical section.
        ADVISORY_LOCK = [0x464f, 0x5254].freeze # "FO", "RT"
        # duplicate_schema, and the unique violation on pg_namespace the same race can raise instead.
        DUPLICATE_SCHEMA_STATES = %w[42P06 23505].freeze

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
        rescue ActiveRecord::RecordNotUnique
          # 23505 on pg_namespace, already mapped to its own class by ActiveRecord: another instance
          # created the schema between our IF NOT EXISTS check and the create itself.
          nil
        rescue ActiveRecord::StatementInvalid => e
          raise unless duplicate_schema?(e)
        end

        # By SQLSTATE where the adapter exposes one, so an unrelated failure (no permission to create a
        # schema, say) is not read as a lost race just because its message says "exists".
        def duplicate_schema?(error)
          state = sql_state(error)
          return DUPLICATE_SCHEMA_STATES.include?(state) if state

          /already exists|duplicate/i.match?(error.message)
        end

        def sql_state(error)
          cause = error.cause
          return nil unless cause.respond_to?(:result) && defined?(PG::Result)

          cause.result.error_field(PG::Result::PG_DIAG_SQLSTATE)
        rescue StandardError
          nil
        end

        def apply_pending
          done = applied_migrations
          table = qualified(@table_name)

          Migrations::ALL.each do |migration|
            # The tracking table is shared by every audit table of the database/schema, so the target
            # table belongs in the key: a store configured with another `table_name` must still get its
            # own table created instead of reading someone else's migration as done. Rows written by
            # earlier versions (bare migration name) simply replay, which the `if_not_exists` DDL above
            # makes a no-op.
            key = "#{table}:#{migration[:name]}"
            next if done.include?(key)

            migration[:up].call(@connection, table)
            @connection.execute(
              "INSERT INTO #{@connection.quote_table_name(migrations_table)} (name) " \
              "VALUES (#{@connection.quote(key)})"
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
end
