require 'time'

module ForestAdminAgent
  module AuditTrail
    # SQL-backed storage that both writes every audited change and reads the per-record history back.
    #
    # {#connect!} opens the connection and migrates; the agent factory calls it at boot rather than leaving it
    # to the first write, so a database the agent cannot reach is a startup failure instead of an agent that
    # looks healthy while recording nothing — and, under `critical: true`, instead of one that refuses every
    # write the moment somebody first tries to save something.
    class Store
      DEFAULT_SCHEMA = 'forest'.freeze
      DEFAULT_TABLE = 'audit_logs'.freeze
      COLUMNS = %i[timestamp operation collection record_id status user_id user_first_name
                   user_last_name user_email action_name correlation_key previous_values new_values].freeze
      AUTHOR_COLUMNS = %i[user_id user_first_name user_last_name user_email].freeze

      def initialize(database:, schema: DEFAULT_SCHEMA, table_name: DEFAULT_TABLE)
        @database = database
        @schema = schema
        @table_name = table_name
        @mutex = Mutex.new
        @ready = false
      end

      def connect!
        ensure_ready

        self
      end

      def append(record)
        append_all([record]).first
      end

      # Inserts rows and returns their ids, in the order given. Batched, because a "delete all" snapshot can
      # be thousands of records and the pending/confirm protocol writes each of them twice.
      #
      # The ids are matched to their rows by `record_id` rather than by the order RETURNING happens to come
      # back in, which Postgres does not promise: pairing them positionally would confirm each pending row with
      # another record's diff. One row per record per operation, so that key is unique within a batch — bar a
      # pending create, which has no id yet and is always a batch of one.
      def append_all(records)
        return [] if records.empty?

        rows = records.map { |record| to_row(record) }
        return rows.map { |row| model.create!(row).id } unless batch_returning?(rows)

        returned = model.insert_all(rows, returning: %i[id record_id]).rows.to_h { |id, key| [key, id] }

        rows.map { |row| returned[row[:record_id]] }
      end

      # One insert per row when the ids cannot be matched back: no RETURNING on this adapter (MySQL), or a
      # batch whose record ids are not distinct enough to pair on.
      def batch_returning?(rows)
        return false unless model.connection.supports_insert_returning?

        keys = rows.map { |row| row[:record_id] }

        keys.none?(&:nil?) && keys.uniq.size == keys.size
      end

      def confirm(id, attributes)
        row = model.find_by(id: id)

        row&.update!(**attributes, status: Recording::DONE)
      end

      # A write that turned out to change nothing leaves no trace: the pending row goes rather than sitting
      # there implying the write is unaccounted for.
      def discard(ids)
        model.where(id: ids).delete_all unless ids.empty?
      end

      def list_by_record(collection:, record_id:, skip: 0, limit: nil, user_ids: nil, operations: nil,
                         start_timestamp: nil, end_timestamp: nil, fields: nil, search: nil, order: 'asc', after: nil)
        descending = order.to_s == 'desc'
        # `id` (insertion order) breaks ties on equal timestamps in both directions, keeping pages
        # deterministic and stable.
        relation = scope(collection, record_id, user_ids: user_ids, operations: operations,
                                                start_timestamp: start_timestamp, end_timestamp: end_timestamp,
                                                fields: fields, search: search)
                   .order(timestamp: descending ? :desc : :asc, id: :asc)
                   .offset(skip || 0)
        relation = relation.where(*past_row_condition(after, descending)) if after
        relation = relation.limit(limit) unless limit.nil?

        relation.map { |row| from_row(row) }
      end

      def count_by_record(collection:, record_id:, user_ids: nil, operations: nil, start_timestamp: nil,
                          end_timestamp: nil, fields: nil, search: nil)
        scope(collection, record_id, user_ids: user_ids, operations: operations, start_timestamp: start_timestamp,
                                     end_timestamp: end_timestamp, fields: fields, search: search).count
      end

      # The distinct authors of the entries the current filters match, whatever page is being asked for. The
      # identity comes from the rows themselves, so a user who has since been renamed or removed still reads
      # as they were when they acted.
      def authors_by_record(collection:, record_id:, user_ids: nil, operations: nil, start_timestamp: nil,
                            end_timestamp: nil, fields: nil, search: nil)
        authors(scope(collection, record_id, user_ids: user_ids, operations: operations,
                                             start_timestamp: start_timestamp, end_timestamp: end_timestamp,
                                             fields: fields, search: search))
      end

      # The project-level timeline across `collections`, the ones the caller may read: newest first, or oldest
      # first with `order: 'asc'`, ties broken by id in the same direction. `before` / `after` are the cursor's
      # inclusive bound and `exclude_ids` the rows already served at it.
      def list_timeline(collections:, limit:, order: 'desc', **filters)
        return [] if collections.empty?

        direction = order.to_s == 'asc' ? :asc : :desc

        timeline_scope(collections, **filters).order(timestamp: direction, id: direction).limit(limit)
                                              .map { |row| from_row(row) }
      end

      # The distinct authors of the timeline the filters match, whatever the cursor.
      def timeline_users(collections:, **filters)
        return [] if collections.empty?

        authors(timeline_scope(collections, **filters))
      end

      # Entries recorded strictly after `timestamp`, newest first: what a state reconstruction has to undo.
      # Strictly after, so an entry stamped exactly at the requested instant counts as part of that state
      # instead of being reverted out of it.
      # Confirmed rows only: a pending one records an attempt whose outcome is unknown, and undoing a change
      # that may never have happened would invent a state the record was never in. The history reads keep
      # pending rows — they are evidence, and `status` tells the reader what they are — but a reconstruction
      # cannot act on them.
      def list_since(collection:, record_id:, timestamp:)
        model.where(collection: collection, status: Recording::DONE)
             .where(record_id: record_id)
             .where('timestamp > ?', as_time(timestamp))
             .order(timestamp: :desc, id: :desc)
             .map { |row| from_row(row) }
      end

      def list_by_correlation(collection:, record_id:, correlation_key:)
        list_by_correlations(collection: collection, record_id: record_id, correlation_keys: [correlation_key])
      end

      def list_by_correlations(collection:, record_id:, correlation_keys:)
        return [] if correlation_keys.empty?

        model.where(collection: collection, record_id: record_id, correlation_key: correlation_keys)
             .order(:timestamp, :id)
             .map { |row| from_row(row) }
      end

      private

      # Every filter is an AND, so the count matches exactly what a page of this history holds.
      def scope(collection, record_id, user_ids: nil, operations: nil, start_timestamp: nil, end_timestamp: nil,
                fields: nil, search: nil)
        relation = model.where(collection: collection).where(record_id: record_id)
        relation = relation.where(user_id: user_ids) if user_ids
        relation = relation.where(operation: operations) if operations
        relation = relation.where(Sql::FieldFilter.new(model.connection).condition(fields)) if fields&.any?
        relation = relation.where(Sql::TextSearch.new(model.connection).condition(search)) if search
        # Compare as Time so ActiveRecord casts the bound to the datetime column's storage format
        # (raw ISO strings with a `Z` would compare lexically against the cast rows and never match).
        relation = relation.where('timestamp >= ?', as_time(start_timestamp)) if start_timestamp
        relation = relation.where('timestamp <= ?', as_time(end_timestamp)) if end_timestamp
        relation
      end

      # Each cursor bound and the date filter on its side are both inclusive, so the tighter one wins.
      def timeline_scope(collections, before: nil, after: nil, exclude_ids: nil, user_ids: nil, operations: nil,
                         start_timestamp: nil, end_timestamp: nil, search: nil)
        relation = model.where(collection: collections)
        relation = relation.where(user_id: user_ids) if user_ids
        relation = relation.where(operation: operations) if operations
        relation = relation.where.not(id: exclude_ids) if exclude_ids&.any?
        relation = relation.where(Sql::TextSearch.new(model.connection).condition(search)) if search
        lower = [start_timestamp, after].compact.map { |bound| as_time(bound) }.max
        upper = [end_timestamp, before].compact.map { |bound| as_time(bound) }.min
        relation = relation.where('timestamp >= ?', lower) if lower
        relation = relation.where('timestamp <= ?', upper) if upper
        relation
      end

      def authors(relation)
        relation.where.not(user_id: nil)
                .distinct
                .pluck(*AUTHOR_COLUMNS)
                .map { |values| AUTHOR_COLUMNS.zip(values).to_h }
                .uniq { |author| author[:user_id] }
      end

      # Rows strictly past `row` in the history's own order, so a scan keyed on the last row it read neither
      # repeats nor skips one when entries are written between its reads, as an offset would.
      def past_row_condition(row, descending)
        at = as_time(row[:timestamp])
        past = descending ? '<' : '>'

        ["timestamp #{past} ? OR (timestamp = ? AND id > ?)", at, at, row[:id]]
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

          Sql::AuditConnectionBase.connect_to(@database)
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

      # An AuditRecord is a Struct and a row answers to `[]` too, so the mapping is the column list itself.
      def to_row(record)
        COLUMNS.to_h { |column| [column, record[column]] }
      end

      def from_row(row)
        values = COLUMNS.to_h { |column| [column, row[column]] }
        values[:id] = row.id
        values[:timestamp] = row.timestamp.respond_to?(:iso8601) ? row.timestamp.iso8601(3) : row.timestamp.to_s
        values[:previous_values] ||= {}
        values[:new_values] ||= {}

        AuditRecord.new(**values)
      end
    end
  end
end
