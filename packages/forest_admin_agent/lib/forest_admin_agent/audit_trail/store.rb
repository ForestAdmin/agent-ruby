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
      COLUMNS = %i[timestamp operation collection record_id previous_record_id status user_id user_first_name
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

      def list_by_record(collection:, record_id:, skip: 0, limit: nil, user_ids: nil, start_timestamp: nil,
                         end_timestamp: nil, fields: nil, search: nil, order: 'asc')
        # `id` (insertion order) breaks ties on equal timestamps in both directions, keeping pages
        # deterministic and stable.
        relation = scope(collection, record_id, user_ids: user_ids, start_timestamp: start_timestamp,
                                                end_timestamp: end_timestamp, fields: fields, search: search)
                   .order(timestamp: order.to_s == 'desc' ? :desc : :asc, id: :asc)
                   .offset(skip || 0)
        relation = relation.limit(limit) unless limit.nil?

        relation.map { |row| from_row(row) }
      end

      def count_by_record(collection:, record_id:, user_ids: nil, start_timestamp: nil,
                          end_timestamp: nil, fields: nil, search: nil)
        scope(collection, record_id, user_ids: user_ids, start_timestamp: start_timestamp,
                                     end_timestamp: end_timestamp, fields: fields, search: search).count
      end

      # The distinct authors of the entries the current filters match, whatever page is being asked for. The
      # identity comes from the rows themselves, so a user who has since been renamed or removed still reads
      # as they were when they acted.
      def authors_by_record(collection:, record_id:, user_ids: nil, start_timestamp: nil,
                            end_timestamp: nil, fields: nil, search: nil)
        scope(collection, record_id, user_ids: user_ids, start_timestamp: start_timestamp,
                                     end_timestamp: end_timestamp, fields: fields, search: search)
          .where.not(user_id: nil)
          .distinct
          .pluck(*AUTHOR_COLUMNS)
          .map { |values| AUTHOR_COLUMNS.zip(values).to_h }
          .uniq { |author| author[:user_id] }
      end

      # The ids this record was renamed from, each with the moment it stopped being that id. Walking those back
      # is what lets a history query reach rows written before a rename — they stay under the id they were
      # written with, since that is the id they were true of — and the moment bounds how far: the id it left may
      # have been taken by another record afterwards, whose rows are none of this record's business.
      def renamed_from(collection:, record_id:)
        model.where(collection: collection, record_id: record_id)
             .where.not(previous_record_id: nil)
             .pluck(:previous_record_id, :timestamp, :id)
             .group_by(&:first)
             .map do |id, rows|
               # The row id comes along as the tie-breaker: the trail orders itself by (timestamp, id), so a
               # bound that knew only the timestamp would mean something slightly different from "before".
               _, at, row = rows.max_by { |(_, timestamp, row_id)| [timestamp, row_id] }

               { id: id, until: as_iso(at), until_row: row }
             end
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
             .where(*segments_condition(record_id))
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
      def scope(collection, record_id, user_ids: nil, start_timestamp: nil, end_timestamp: nil,
                fields: nil, search: nil)
        relation = model.where(collection: collection).where(*segments_condition(record_id))
        relation = relation.where(user_id: user_ids) if user_ids
        relation = relation.where(Sql::FieldFilter.new(model.connection).condition(fields)) if fields&.any?
        relation = relation.where(Sql::TextSearch.new(model.connection).condition(search)) if search
        # Compare as Time so ActiveRecord casts the bound to the datetime column's storage format
        # (raw ISO strings with a `Z` would compare lexically against the cast rows and never match).
        relation = relation.where('timestamp >= ?', as_time(start_timestamp)) if start_timestamp
        relation = relation.where('timestamp <= ?', as_time(end_timestamp)) if end_timestamp
        relation
      end

      def as_time(value)
        value.is_a?(::Time) ? value : ::Time.iso8601(value.to_s)
      end

      def as_iso(value)
        value.respond_to?(:iso8601) ? value.iso8601(3) : value.to_s
      end

      # One record's history is its current id plus every id it was renamed from, each earlier one only up to
      # the rename: `record_id = '7' OR (record_id = '1' AND timestamp <= …)`. A plain `IN` would hand over the
      # rows of whichever record holds that id now.
      #
      # Takes an id, several, or segments — `{ id:, until: }` — so a caller that has no rename to care about
      # simply passes the id.
      def segments_condition(record_id)
        binds = []
        sql = Array(record_id).map { |value| value.is_a?(Hash) ? value : { id: value, until: nil } }.map do |segment|
          binds << segment[:id]
          next 'record_id = ?' unless segment[:until]

          binds << as_time(segment[:until])
          # Same millisecond as the rename, and the id says which side of it a row falls on: another record
          # taking the abandoned key that fast would otherwise land in this record's history.
          next '(record_id = ? AND timestamp <= ?)' unless segment[:until_row]

          binds << as_time(segment[:until]) << segment[:until_row]
          '(record_id = ? AND (timestamp < ? OR (timestamp = ? AND id <= ?)))'
        end

        [sql.join(' OR '), *binds]
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
