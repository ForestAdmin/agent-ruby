require 'securerandom'
require 'time'

module ForestAdminAuditTrail
  # Datasource-agnostic capture layer. Instruments every collection (or a single one) through the
  # Forest customizer hooks, computes the minimal before/after diff for each change and appends an
  # {AuditRecord} to the configured store.
  #
  # Usage (datasource level — audits every collection):
  #   agent.use(ForestAdminAuditTrail::Plugin, store: my_store)
  #
  # Options:
  #   store:  object responding to #append(AuditRecord). Defaults to a store that logs each record.
  #   redact: { 'collection_name' => ['field', ...] } — values masked while still recording the change.
  class Plugin
    REDACTED = '[redacted]'.freeze

    def run(datasource_customizer, collection_customizer = nil, options = {})
      options ||= {}
      @store = options[:store] || Stores::LogStore.new
      @redact = options[:redact] || {}

      collections = if collection_customizer
                      [collection_customizer]
                    else
                      datasource_customizer.collections.values
                    end

      collections.each { |collection| instrument(collection) }
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
      redacted = @redact[name] || []

      add_create_hook(collection_customizer, columns, primary_keys, name, redacted)
      add_update_hooks(collection_customizer, columns, primary_keys, name, redacted, projection)
      add_delete_hooks(collection_customizer, columns, primary_keys, name, redacted, projection)
    end

    def add_create_hook(collection_customizer, columns, primary_keys, name, redacted)
      plugin = self
      collection_customizer.add_hook('After', 'Create') do |context|
        plugin.send(
          :emit,
          context.caller, 'create', name,
          plugin.send(:record_id, context.record, primary_keys),
          {},
          plugin.send(:pick, context.record, columns),
          redacted
        )
      end
    end

    def add_update_hooks(collection_customizer, columns, primary_keys, name, redacted, projection)
      plugin = self

      collection_customizer.add_hook('Before', 'Update') do |context|
        before = context.collection.list(context.filter, projection)
        plugin.send(:pending)[context.filter] = before
      end

      collection_customizer.add_hook('After', 'Update') do |context|
        before = plugin.send(:pending).delete(context.filter) || []
        patch = context.patch

        before.each do |record|
          delta = ForestAdminAuditTrail::Diff.changed_values(record, patch, columns)
          next if delta[:new_values].empty?

          plugin.send(
            :emit,
            context.caller, 'update', name,
            plugin.send(:record_id, record, primary_keys),
            delta[:previous_values], delta[:new_values],
            redacted
          )
        end
      end
    end

    def add_delete_hooks(collection_customizer, columns, primary_keys, name, redacted, projection)
      plugin = self

      collection_customizer.add_hook('Before', 'Delete') do |context|
        before = context.collection.list(context.filter, projection)
        plugin.send(:pending)[context.filter] = before
      end

      collection_customizer.add_hook('After', 'Delete') do |context|
        before = plugin.send(:pending).delete(context.filter) || []

        before.each do |record|
          plugin.send(
            :emit,
            context.caller, 'delete', name,
            plugin.send(:record_id, record, primary_keys),
            plugin.send(:pick, record, columns),
            {},
            redacted
          )
        end
      end
    end

    # Snapshots taken in a "before" hook and consumed in the matching "after" hook. Keyed by the
    # filter object, which the hook decorator passes unchanged to both hooks within the same thread.
    def pending
      Thread.current[:forest_audit_trail_snapshots] ||= {}.compare_by_identity
    end

    def emit(caller, operation, collection, record_id, previous_values, new_values, redacted)
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
