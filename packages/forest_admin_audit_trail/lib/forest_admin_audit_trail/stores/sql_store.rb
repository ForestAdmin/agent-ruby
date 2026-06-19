require 'time'

module ForestAdminAuditTrail
  module Stores
    # SQL-backed store that both writes every audited change and reads the per-record history back.
    #
    # Construction is cheap; the connection is opened lazily on the first append or read, at which
    # point the `forest` schema and the `audit_logs` table are created/evolved through migrations.
    # Pass the SAME instance to the plugin (`store:`) and to the agent (`audit_trail: { store: }`) so
    # writes and the record-history route agree on storage.
    class SqlStore
      DEFAULT_SCHEMA = 'forest'.freeze
      DEFAULT_TABLE = 'audit_logs'.freeze

      def initialize(connection_string:, schema: DEFAULT_SCHEMA, table_name: DEFAULT_TABLE)
        @connection_string = connection_string
        @schema = schema
        @table_name = table_name
        @mutex = Mutex.new
        @ready = false
      end

      def append(record)
        model.create!(to_row(record))
      end

      def list_by_record(collection:, record_id:, skip: 0, limit: nil,
                         user_ids: nil, start_timestamp: nil, end_timestamp: nil, order: 'asc')
        # `id` (insertion order) breaks ties on equal timestamps in both directions, keeping pages
        # deterministic and stable.
        relation = scope(collection, record_id, user_ids, start_timestamp, end_timestamp)
                   .order(timestamp: order.to_s == 'desc' ? :desc : :asc, id: :asc)
                   .offset(skip || 0)
        relation = relation.limit(limit) unless limit.nil?

        relation.map { |row| from_row(row) }
      end

      def count_by_record(collection:, record_id:, user_ids: nil, start_timestamp: nil, end_timestamp: nil)
        scope(collection, record_id, user_ids, start_timestamp, end_timestamp).count
      end

      def list_by_correlation(collection:, record_id:, correlation_key:)
        model.where(collection: collection, record_id: record_id, correlation_key: correlation_key)
             .order(:timestamp, :id)
             .map { |row| from_row(row) }
      end

      def list_by_correlations(collection:, record_id:, correlation_keys:)
        return [] if correlation_keys.empty?

        model.where(collection: collection, record_id: record_id, correlation_key: correlation_keys)
             .order(:timestamp, :id)
             .map { |row| from_row(row) }
      end

      private

      def scope(collection, record_id, user_ids, start_timestamp, end_timestamp)
        relation = model.where(collection: collection, record_id: record_id)
        relation = relation.where(user_id: user_ids) if user_ids
        # Compare as Time so ActiveRecord casts the bound to the datetime column's storage format
        # (raw ISO strings with a `Z` would compare lexically against the cast rows and never match).
        relation = relation.where('timestamp >= ?', as_time(start_timestamp)) if start_timestamp
        relation = relation.where('timestamp <= ?', as_time(end_timestamp)) if end_timestamp
        relation
      end

      def as_time(value)
        value.is_a?(::Time) ? value : ::Time.iso8601(value.to_s)
      end

      def model
        ensure_ready
        @model
      end

      def ensure_ready
        return if @ready

        @mutex.synchronize do
          return if @ready

          Sql::AuditConnectionBase.establish_connection(@connection_string)
          connection = Sql::AuditConnectionBase.connection
          Sql::Migrator.new(connection, schema: schema_for(connection), table_name: @table_name).run
          @model = build_model(qualified(connection))
          @ready = true
        end
      end

      # A per-instance concrete subclass bound to this store's own table, so distinct stores can't
      # clobber each other's table name. reset_column_information drops stale metadata for the table
      # the migration just created/evolved.
      def build_model(table)
        Class.new(Sql::AuditLog) { self.table_name = table }.tap(&:reset_column_information)
      end

      def schema_for(connection)
        connection.adapter_name.downcase.include?('postgres') ? @schema : nil
      end

      def qualified(connection)
        schema = schema_for(connection)
        schema ? "#{schema}.#{@table_name}" : @table_name
      end

      def to_row(record)
        {
          timestamp: record.timestamp,
          operation: record.operation,
          collection: record.collection,
          record_id: record.record_id,
          user_id: record.user_id,
          correlation_key: record.correlation_key,
          previous_values: record.previous_values,
          new_values: record.new_values
        }
      end

      def from_row(row)
        AuditRecord.new(
          timestamp: row.timestamp.respond_to?(:iso8601) ? row.timestamp.iso8601(3) : row.timestamp.to_s,
          operation: row.operation,
          collection: row.collection,
          record_id: row.record_id,
          user_id: row.user_id,
          correlation_key: row.correlation_key,
          previous_values: row.previous_values || {},
          new_values: row.new_values || {}
        )
      end
    end
  end
end
