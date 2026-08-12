module ForestAdminAgent
  module AuditTrail
    # Datasource-agnostic capture layer, installed by the agent factory as soon as an audit-trail
    # database is configured. It instruments every collection through the Forest customizer hooks, so
    # it behaves the same whatever the audited datasource is (ActiveRecord, Mongoid, ...), computes the
    # minimal before/after diff for each change and appends an {AuditRecord} to the store.
    class Capture
      include Recording

      # ponytail: 16 deep is far past any legitimate nesting; raise it if one ever gets that far.
      MAX_SNAPSHOTS = 16

      # Signature imposed by DatasourceCustomizer#use; the agent always instruments the whole datasource.
      def run(datasource_customizer, _collection_customizer = nil, options = {})
        @store = options[:store]
        @redact = options[:redact] || {}

        datasource_customizer.collections.each_value { |collection| instrument(collection) }
      end

      private

      def instrument(collection_customizer)
        schema = collection_customizer.collection.schema
        # Writable columns only: Forest audits what it writes. Read-only fields cover computed/virtual
        # fields and DB-managed columns, none of which Forest mutates.
        columns = schema[:fields].select do |_name, field|
          field.type == 'Column' && !field.is_read_only
        end.keys
        primary_keys = ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(collection_customizer.collection)
        # Reads must carry the primary keys (even read-only ones) so the record id can be built; the
        # diff itself stays restricted to the writable columns.
        projection = ForestAdminDatasourceToolkit::Components::Query::Projection.new(
          (primary_keys + columns).uniq
        )
        name = collection_customizer.name

        add_create_hook(collection_customizer, columns, primary_keys, name)
        add_update_hooks(collection_customizer, columns, primary_keys, name, projection)
        add_delete_hooks(collection_customizer, columns, primary_keys, name, projection)
      end

      def add_create_hook(collection_customizer, columns, primary_keys, name)
        collection_customizer.add_hook('After', 'Create') do |context|
          emit(
            context.caller, 'create', name, record_id(context.record, primary_keys),
            {}, pick(context.record, columns)
          )
        end
      end

      def add_update_hooks(collection_customizer, columns, primary_keys, name, projection)
        collection_customizer.add_hook('Before', 'Update') do |context|
          # Snapshot the patch here: installed last, this hook sees what actually gets written, while
          # the after-context is handed the original patch the caller sent.
          push_snapshot(records: snapshot(context, projection), patch: context.patch)
        end

        collection_customizer.add_hook('After', 'Update') do |context|
          snapshot = snapshots.pop

          snapshot&.fetch(:records)&.each do |record|
            delta = Diff.changed_values(record, snapshot[:patch], columns)
            next if delta[:new_values].empty?

            emit(
              context.caller, 'update', name, record_id(record, primary_keys),
              delta[:previous_values], delta[:new_values]
            )
          end
        end
      end

      def add_delete_hooks(collection_customizer, columns, primary_keys, name, projection)
        collection_customizer.add_hook('Before', 'Delete') do |context|
          push_snapshot(records: snapshot(context, projection))
        end

        collection_customizer.add_hook('After', 'Delete') do |context|
          snapshot = snapshots.pop

          snapshot&.fetch(:records)&.each do |record|
            emit(
              context.caller, 'delete', name, record_id(record, primary_keys),
              pick(record, columns), {}
            )
          end
        end
      end

      # An empty snapshot on failure rather than no snapshot at all: the after hook pops unconditionally,
      # so skipping the push would pair it with an unrelated entry.
      def snapshot(context, projection)
        audit_safely { context.collection.list(context.filter, projection) } || []
      end

      # Snapshots taken in a "before" hook and consumed in the matching "after" hook. Both bracket one
      # operation on one thread, so a LIFO stack pairs them without relying on the filter object
      # reaching both hooks unchanged. An operation raising in between strands its entry, hence the cap.
      def push_snapshot(snapshot)
        stack = snapshots
        stack.shift while stack.size >= MAX_SNAPSHOTS
        stack.push(snapshot)
      end

      def snapshots
        Thread.current[:forest_audit_trail_snapshots] ||= []
      end

      def emit(caller, operation, collection, record_id, previous_values, new_values)
        redacted = @redact[collection] || []

        audit_safely do
          @store.append(
            AuditRecord.new(
              timestamp: now,
              operation: operation,
              collection: collection,
              record_id: record_id,
              user_id: caller&.id,
              correlation_key: correlation_key_for(caller),
              previous_values: redact(previous_values, redacted),
              new_values: redact(new_values, redacted)
            )
          )
        end
      end

      def record_id(record, primary_keys)
        primary_keys.map { |pk| record[pk].to_s }.join('|')
      end

      def pick(record, columns)
        columns.to_h { |column| [column, record[column]] }
      end
    end
  end
end
