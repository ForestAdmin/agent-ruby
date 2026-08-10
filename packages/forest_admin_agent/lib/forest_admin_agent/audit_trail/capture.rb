require 'securerandom'
require 'time'

module ForestAdminAgent
  module AuditTrail
    # Datasource-agnostic capture layer, installed by the agent factory as soon as an audit-trail
    # database is configured. It instruments every collection through the Forest customizer hooks, so
    # it behaves the same whatever the audited datasource is (ActiveRecord, Mongoid, ...), computes the
    # minimal before/after diff for each change and appends an {AuditRecord} to the store.
    class Capture
      REDACTED = '[redacted]'.freeze

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
          pending[context.filter] = context.collection.list(context.filter, projection)
        end

        collection_customizer.add_hook('After', 'Update') do |context|
          before = pending.delete(context.filter) || []
          patch = context.patch

          before.each do |record|
            delta = Diff.changed_values(record, patch, columns)
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
          pending[context.filter] = context.collection.list(context.filter, projection)
        end

        collection_customizer.add_hook('After', 'Delete') do |context|
          before = pending.delete(context.filter) || []

          before.each do |record|
            emit(
              context.caller, 'delete', name, record_id(record, primary_keys),
              pick(record, columns), {}
            )
          end
        end
      end

      # Snapshots taken in a "before" hook and consumed in the matching "after" hook. Keyed by the
      # filter object, which the hook decorator passes unchanged to both hooks within the same thread.
      def pending
        Thread.current[:forest_audit_trail_snapshots] ||= {}.compare_by_identity
      end

      def emit(caller, operation, collection, record_id, previous_values, new_values)
        redacted = @redact[collection] || []

        @store.append(
          AuditRecord.new(
            timestamp: Time.now.utc.iso8601(3),
            operation: operation,
            collection: collection,
            record_id: record_id,
            user_id: caller&.id,
            # Same id for every change made within one request — set on the caller by the agent
            # (see CallerParser), mirroring the Node agent's caller.requestId.
            correlation_key: correlation_key_for(caller),
            previous_values: redact(previous_values, redacted),
            new_values: redact(new_values, redacted)
          )
        )
      end

      def correlation_key_for(caller)
        (caller.respond_to?(:request_id) && caller.request_id) || SecureRandom.uuid
      end

      def record_id(record, primary_keys)
        primary_keys.map { |pk| record[pk].to_s }.join('|')
      end

      def pick(record, columns)
        columns.to_h { |column| [column, record[column]] }
      end

      def redact(values, redacted_fields)
        return values if redacted_fields.empty?

        values.each_with_object({}) do |(field, value), result|
          result[field] = redacted_fields.include?(field) ? REDACTED : value
        end
      end
    end
  end
end
