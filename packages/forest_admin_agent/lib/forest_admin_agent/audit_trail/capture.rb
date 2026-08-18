module ForestAdminAgent
  module AuditTrail
    # Datasource-agnostic capture layer, installed by the agent factory as soon as an audit-trail database is
    # configured. It instruments every collection through the Forest customizer hooks, so it behaves the same
    # whatever the audited datasource is (ActiveRecord, Mongoid, ...).
    #
    # Every operation is recorded twice: a PENDING row before the write, confirmed DONE after it. One code
    # path in both `critical` modes, so `status` always means the same thing — and what the protocol buys is
    # that no write goes unaudited, not that every row holds exact after-values. A row left pending says the
    # write may or may not have landed, which is evidence rather than a defect.
    class Capture
      include Recording

      # Signature imposed by DatasourceCustomizer#use; the agent always instruments the whole datasource.
      def run(datasource_customizer, _collection_customizer = nil, options = {})
        @store = options[:store]
        @redact = options[:redact] || {}
        @snapshots = Snapshots.new

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
        target = { columns: columns, primary_keys: primary_keys, projection: projection,
                   name: collection_customizer.name }

        add_create_hooks(collection_customizer, target)
        add_update_hooks(collection_customizer, target)
        add_delete_hooks(collection_customizer, target)
      end

      # The "after" hooks are prepended: `execute_after` stops at the first exception, so a customization
      # raising in its own after hook would otherwise drop the record of a write that already happened.
      # The "before" hooks stay appended, so they read the data, filter and patch every other customization
      # has had its say on.
      def add_create_hooks(collection_customizer, target)
        collection_customizer.add_hook('Before', 'Create') do |context|
          # No record id yet — that is what the column being nullable is for.
          rows = [{ record_id: nil, new_values: pick(context.data, target[:columns]) }]

          @snapshots.push(context.data, ids: pending_rows(context.caller, 'create', target[:name], rows))
        end

        collection_customizer.add_hook('After', 'Create', prepend: true) do |context|
          pending = @snapshots.pop_for(context.data)
          next unless pending

          confirm(pending[:ids].first,
                  record_id: record_id(context.record, target[:primary_keys]),
                  new_values: redacted(target[:name], pick(context.record, target[:columns])))
        end
      end

      def add_update_hooks(collection_customizer, target)
        collection_customizer.add_hook('Before', 'Update') do |context|
          records = @snapshots.take(context, target[:projection])
          @snapshots.push(
            context.filter,
            records: records,
            patch: context.patch,
            ids: pending_rows(
              context.caller, 'update', target[:name],
              records.map do |record|
                { record_id: record_id(record, target[:primary_keys]),
                  previous_values: pick(record, context.patch.keys & target[:columns]),
                  new_values: pick(context.patch, target[:columns]) }
              end
            )
          )
        end

        collection_customizer.add_hook('After', 'Update', prepend: true) do |context|
          pending = @snapshots.pop_for(context.filter)
          next unless pending

          confirm_updates(context, pending, target)
        end
      end

      def add_delete_hooks(collection_customizer, target)
        collection_customizer.add_hook('Before', 'Delete') do |context|
          records = @snapshots.take(context, target[:projection])
          @snapshots.push(
            context.filter,
            records: records,
            ids: pending_rows(
              context.caller, 'delete', target[:name],
              records.map do |record|
                { record_id: record_id(record, target[:primary_keys]),
                  previous_values: pick(record, target[:columns]) }
              end
            )
          )
        end

        collection_customizer.add_hook('After', 'Delete', prepend: true) do |context|
          pending = @snapshots.pop_for(context.filter)
          next unless pending

          pending[:ids].each { |id| confirm(id) }
        end
      end

      # The diff is taken against the record as persisted, not the patch that was requested, so a value the
      # datasource normalised or a decorator rewrote is recorded as what actually landed. The id is packed from
      # those same values, so an update that changed a primary key files the row under the id the history will
      # be queried by.
      def confirm_updates(context, pending, target)
        pks = target[:primary_keys]
        persisted = reread(context, pending[:records], pending[:patch], target)
        empty = []

        pending[:records].each_with_index do |record, index|
          # No row read back: the write may or may not have landed, and inventing after-values from the patch
          # would confirm — or worse, discard — a row for something that may never have happened. Left pending,
          # which is exactly what that state means.
          after = persisted[record_id(record.merge(pending[:patch]), pks)]
          next if after.nil?

          delta = Diff.changed_values(record, after, target[:columns])

          if delta[:new_values].empty?
            empty << pending[:ids][index]
          else
            before_id = record_id(record, pks)
            after_id = record_id(after, pks)

            confirm(pending[:ids][index],
                    record_id: after_id,
                    # Only when the key actually moved, so a history query can walk back to the rows filed
                    # under the id this record used to have.
                    previous_record_id: after_id == before_id ? nil : before_id,
                    previous_values: redacted(target[:name], delta[:previous_values]),
                    new_values: redacted(target[:name], delta[:new_values]))
          end
        end

        audit_safely { @store.discard(empty.compact) } if empty.any?
      end

      # Reads the updated records back in one query, keyed by their own id, so each snapshot can find what
      # actually landed — including when the patch moved a primary key.
      def reread(context, records, patch, target)
        pks = target[:primary_keys]
        return {} if records.empty?

        audit_safely do
          condition = ids_condition(pks, records.map { |record| record.merge(patch).slice(*pks) })
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(condition_tree: condition)

          context.collection.list(filter, target[:projection]).to_h { |row| [record_id(row, pks), row] }
        end || {}
      end

      # Built from the primary keys the instrumentation already resolved, rather than through
      # ConditionTreeFactory, which would need the underlying collection a hook context does not hand out.
      def ids_condition(primary_keys, ids)
        leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
        factory = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::ConditionTreeFactory

        operators = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators

        if primary_keys.size == 1
          key = primary_keys.first

          leaf.new(key, operators::IN, ids.map { |id| id[key] }.uniq)
        else
          factory.union(
            ids.map { |id| factory.intersect(id.map { |key, value| leaf.new(key, operators::EQUAL, value) }) }
          )
        end
      end

      # The one place the audit trail may refuse an operation, and only under `critical: true`: if we cannot
      # record that a write is about to happen, the write does not happen.
      def pending_rows(caller, operation, collection, rows)
        timestamp = now
        correlation_key = correlation_key_for(caller)
        identity = identity_of(caller)

        AuditTrail.gate do
          @store.append_all(
            rows.map do |row|
              AuditRecord.new(
                timestamp: timestamp, operation: operation, collection: collection, status: PENDING,
                correlation_key: correlation_key, record_id: row[:record_id],
                previous_values: redacted(collection, row[:previous_values] || {}),
                new_values: redacted(collection, row[:new_values] || {}),
                **identity
              )
            end
          )
        end || []
      end

      def confirm(id, attributes = {})
        return unless id

        audit_safely { @store.confirm(id, attributes) }
      end

      def redacted(collection, values)
        redact(values, @redact[collection] || [])
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
