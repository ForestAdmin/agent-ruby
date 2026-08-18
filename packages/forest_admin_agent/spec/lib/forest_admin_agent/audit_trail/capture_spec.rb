require 'spec_helper'

module ForestAdminAgent
  module AuditTrail
    describe Capture do
      let(:column_schema) { ForestAdminDatasourceToolkit::Schema::ColumnSchema }
      # The hook decorator hands the same filter (or data) object to both contexts, which is what pairs a
      # snapshot with its own after hook — so the helpers share one per operation, as production does.
      let(:filter) { new_filter }

      # Rows keyed by position, which stands in for the row id the store hands back.
      let(:store) do
        Class.new do
          attr_reader :records, :discarded

          def initialize
            @records = []
            @discarded = []
          end

          def append_all(rows)
            first = @records.size
            @records.concat(rows)

            (first...@records.size).to_a
          end

          def confirm(id, attributes)
            attributes.each { |key, value| @records[id][key] = value }
            @records[id][:status] = ForestAdminAgent::AuditTrail::Recording::DONE
          end

          def discard(ids)
            @discarded.concat(ids)
          end
        end.new
      end

      let(:fields) do
        {
          'id' => column_schema.new(column_type: 'Number', is_primary_key: true, is_read_only: true),
          'name' => column_schema.new(column_type: 'String'),
          'address' => column_schema.new(column_type: 'Json')
        }
      end

      let(:hooks) { {} }
      let(:registrations) { [] }
      let(:collection) { double('collection') }
      let(:caller_double) do
        double('caller', id: 42, first_name: 'Ada', last_name: 'L', email: 'ada@test', request_id: 'req-xyz')
      end

      # What a hook context really hands out: the caller is already bound, so `list` takes
      # (filter, projection). A verifying double keeps that contract honest.
      let(:relaxed_collection) do
        instance_double(ForestAdminDatasourceCustomizer::Context::RelaxedWrappers::RelaxedCollection)
      end

      let(:collection_customizer) do
        customizer = double('CollectionCustomizer', name: 'companies', collection: collection)
        allow(customizer).to receive(:add_hook) do |position, type, prepend: false, &block|
          registrations << [position, type, prepend]
          hooks["#{position}_#{type}"] = block
        end
        customizer
      end

      let(:datasource_customizer) do
        double('DatasourceCustomizer', collections: { 'companies' => collection_customizer })
      end

      before do
        Thread.current[:forest_audit_trail_snapshots] = nil
        allow(collection).to receive(:schema).and_return({ fields: fields })
        described_class.new.run(datasource_customizer, nil, store: store)
      end

      def new_filter
        ForestAdminDatasourceToolkit::Components::Query::Filter.new(condition_tree: nil)
      end

      def before_hook(type, patch: nil, data: nil, on: filter)
        hooks["Before_#{type}"].call(
          double('before', caller: caller_double, filter: on, collection: relaxed_collection,
                           patch: patch, data: data)
        )
      end

      def after_hook(type, record: nil, data: nil, on: filter)
        hooks["After_#{type}"].call(
          double('after', caller: caller_double, filter: on, collection: relaxed_collection,
                          record: record, data: data)
        )
      end

      # execute_after stops at the first exception, so being last would mean losing the record of a write that
      # already happened whenever another customization raises in its own after hook.
      it 'registers its after hooks ahead of the ones already there, and its before hooks after them' do
        expect(registrations).to contain_exactly(
          ['Before', 'Create', false], ['After', 'Create', true],
          ['Before', 'Update', false], ['After', 'Update', true],
          ['Before', 'Delete', false], ['After', 'Delete', true]
        )
      end

      describe 'creating a record' do
        it 'records the attempt before the write, with no id yet' do
          before_hook('Create', data: { 'name' => 'Acme' })

          row = store.records.last
          expect(row.status).to eq(Recording::PENDING)
          expect(row.operation).to eq('create')
          expect(row.record_id).to be_nil
          expect(row.new_values).to eq({ 'name' => 'Acme', 'address' => nil })
        end

        it 'confirms it with the id and the record that landed' do
          data = { 'name' => 'Acme' }
          before_hook('Create', data: data)
          after_hook('Create', record: { 'id' => 1, 'name' => 'Acme', 'address' => { 'city' => 'Paris' } },
                               data: data)

          row = store.records.last
          expect(row.status).to eq(Recording::DONE)
          expect(row.record_id).to eq('1')
          expect(row.new_values).to eq({ 'name' => 'Acme', 'address' => { 'city' => 'Paris' } })
        end

        it 'denormalises who acted' do
          before_hook('Create', data: { 'name' => 'Acme' })

          expect(store.records.last.user_email).to eq('ada@test')
          expect(store.records.last.correlation_key).to eq('req-xyz')
        end

        # A write outside any request belongs to no request: inventing a key would make the row look like a
        # single-row request of its own.
        it 'leaves the correlation key empty when the caller carries none' do
          allow(caller_double).to receive(:request_id).and_return(nil)

          before_hook('Create', data: { 'name' => 'Acme' })

          expect(store.records.last.correlation_key).to be_nil
        end
      end

      describe 'updating records' do
        def update(before:, persisted:, patch:)
          allow(relaxed_collection).to receive(:list).and_return(before, persisted)
          before_hook('Update', patch: patch)
          after_hook('Update')

          store.records
        end

        it 'records one pending row per matched record before the write' do
          allow(relaxed_collection).to receive(:list).and_return([{ 'id' => 1, 'name' => 'Acme' },
                                                                  { 'id' => 2, 'name' => 'Other' }])
          before_hook('Update', patch: { 'name' => 'Z' })

          expect(store.records.map(&:record_id)).to eq(%w[1 2])
          expect(store.records.map(&:status).uniq).to eq([Recording::PENDING])
        end

        # The diff is taken against the record as persisted, so normalisation and decorator side effects are
        # what gets recorded — not merely what was asked for.
        it 'diffs against the record as persisted, not the requested patch' do
          rows = update(before: [{ 'id' => 1, 'name' => 'acme' }],
                        persisted: [{ 'id' => 1, 'name' => 'ACME NORMALISED' }],
                        patch: { 'name' => 'Acme' })

          # No rename, so nothing to remember.
          expect(rows.last.previous_record_id).to be_nil
          expect(rows.last.status).to eq(Recording::DONE)
          expect(rows.last.previous_values).to eq({ 'name' => 'acme' })
          expect(rows.last.new_values).to eq({ 'name' => 'ACME NORMALISED' })
        end

        # Otherwise the row would be filed under an id History never queries.
        context 'when the primary key itself is writable' do
          let(:fields) do
            {
              'id' => column_schema.new(column_type: 'Number', is_primary_key: true),
              'name' => column_schema.new(column_type: 'String')
            }
          end

          it 'files the row under the id the record ended up with, remembering the one it left' do
            rows = update(before: [{ 'id' => 1, 'name' => 'Acme' }],
                          persisted: [{ 'id' => 7, 'name' => 'Acme' }],
                          patch: { 'id' => 7 })

            expect(rows.last.record_id).to eq('7')
            expect(rows.last.new_values).to eq({ 'id' => 7 })
            # How a history query reaches the rows written while it was still 1.
            expect(rows.last.previous_record_id).to eq('1')
          end
        end

        # Confirming from the patch would claim values that may never have been written; discarding would erase
        # the evidence that something was attempted.
        it 'leaves the row pending when the record cannot be read back' do
          rows = update(before: [{ 'id' => 1, 'name' => 'Acme' }], persisted: [], patch: { 'name' => 'Z' })

          expect(rows.last.status).to eq(Recording::PENDING)
          expect(store.discarded).to be_empty
        end

        # Nothing changed, so nothing is audited: the pending row goes rather than sitting there implying the
        # write is unaccounted for.
        it 'discards the pending row when the write changed nothing' do
          update(before: [{ 'id' => 1, 'name' => 'Acme' }],
                 persisted: [{ 'id' => 1, 'name' => 'Acme' }],
                 patch: { 'name' => 'Acme' })

          expect(store.discarded).to eq([0])
        end
      end

      describe 'deleting records' do
        it 'records the rows before the write and settles them after' do
          allow(relaxed_collection).to receive(:list).and_return([{ 'id' => 7, 'name' => 'Gone',
                                                                    'address' => nil }])

          before_hook('Delete')
          expect(store.records.last.status).to eq(Recording::PENDING)

          after_hook('Delete')
          row = store.records.last
          expect(row.status).to eq(Recording::DONE)
          expect(row.operation).to eq('delete')
          expect(row.previous_values).to eq({ 'name' => 'Gone', 'address' => nil })
        end
      end

      describe 'when the audit database is unreachable' do
        before { allow(store).to receive(:append_all).and_raise(StandardError, 'audit db is down') }

        # Knowing what an operation is about to touch is part of being able to record it.
        it 'refuses the operation when the snapshot cannot even be read and critical is on' do
          allow(ForestAdminAgent::AuditTrail).to receive(:critical?).and_return(true)
          allow(relaxed_collection).to receive(:list).and_raise(StandardError, 'datasource down')

          expect { before_hook('Delete') }.to raise_error(StandardError, 'datasource down')
        end

        it 'lets the write through, logging the failure, when critical is off' do
          logger = instance_spy(Services::LoggerService)
          allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)

          expect { before_hook('Create', data: { 'name' => 'Acme' }) }.not_to raise_error
          expect(logger).to have_received(:log).with('Error', /audit db is down/)
        end

        # Nothing has been written yet, so refusing costs nothing to repair.
        it 'refuses the operation when critical is on' do
          allow(ForestAdminAgent::AuditTrail).to receive(:critical?).and_return(true)

          expect { before_hook('Create', data: { 'name' => 'Acme' }) }
            .to raise_error(StandardError, 'audit db is down')
        end
      end

      describe 'a selection wider than the cap' do
        let(:cap) { ForestAdminAgent::AuditTrail::MAX_RECORDS_PER_OPERATION }

        it 'audits up to the cap and says how many it left out' do
          logger = instance_spy(Services::LoggerService)
          allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
          matched = (1..(cap + 1)).map { |id| { 'id' => id, 'name' => "n#{id}" } }
          allow(relaxed_collection).to receive_messages(list: matched, aggregate: [{ 'value' => cap + 25 }])

          before_hook('Delete')

          expect(store.records.size).to eq(cap)
          expect(logger).to have_received(:log).with('Warn', /#{cap} records audited, 25 skipped/)
        end

        # Auditing 500 of them while the write touches every match breaks the one invariant critical exists
        # for, so the operation is refused instead — before the write, with nothing to repair.
        it 'refuses the operation when critical is on' do
          allow(ForestAdminAgent::AuditTrail).to receive(:critical?).and_return(true)
          allow(relaxed_collection).to receive(:list).and_return((1..(cap + 1)).map { |id| { 'id' => id } })

          expect { before_hook('Delete') }.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException, /cannot record an operation touching more/
          )
        end

        it 'asks for one more than the cap, so it can tell it was truncated' do
          allow(relaxed_collection).to receive(:list).and_return([])

          before_hook('Delete')

          expect(relaxed_collection).to have_received(:list) do |filter, _projection|
            expect(filter.page.limit).to eq(cap + 1)
          end
        end
      end

      it 'masks redacted fields while still recording the change' do
        described_class.new.run(datasource_customizer, nil, store: store, redact: { 'companies' => ['name'] })
        before_hook('Create', data: { 'name' => 'Secret' })

        expect(store.records.last.new_values['name']).to eq(Recording::REDACTED)
      end

      # A write nested inside another, rescued after it failed, leaves its snapshot behind. Taking the newest
      # entry would confirm that failed operation's rows as done and strand the outer operation's own — both
      # of them lies.
      it 'settles its own operation, not a failed inner one left on the stack' do
        outer = new_filter
        inner = new_filter
        allow(relaxed_collection).to receive(:list).and_return(
          [{ 'id' => 1, 'name' => 'outer' }],
          [{ 'id' => 2, 'name' => 'inner' }],
          [{ 'id' => 1, 'name' => 'outer written' }]
        )

        before_hook('Update', patch: { 'name' => 'outer written' }, on: outer)
        before_hook('Update', patch: { 'name' => 'never written' }, on: inner)
        after_hook('Update', on: outer)

        settled = store.records.select { |row| row.status == Recording::DONE }
        expect(settled.map(&:record_id)).to eq(['1'])
        expect(settled.last.new_values).to eq({ 'name' => 'outer written' })
        # The inner write may or may not have landed, which is what pending says.
        expect(store.records.map(&:record_id).zip(store.records.map(&:status))).to include(['2', Recording::PENDING])
      end

      # A customization replacing the filter leaves nothing to match on: our before hook saw the replacement,
      # the after context carries the original. One operation in flight is unambiguous, so it still pairs.
      it 'still settles a single operation whose filter was replaced' do
        allow(relaxed_collection).to receive(:list).and_return(
          [{ 'id' => 1, 'name' => 'Acme' }], [{ 'id' => 1, 'name' => 'Z' }]
        )

        before_hook('Update', patch: { 'name' => 'Z' }, on: new_filter)
        after_hook('Update', on: new_filter)

        expect(store.records.last.status).to eq(Recording::DONE)
      end

      # Replaced *and* nested: nothing identifies which entry is ours, so neither is confirmed rather than the
      # wrong one being marked done.
      it 'leaves both pending when it cannot tell which operation is which' do
        allow(relaxed_collection).to receive(:list).and_return([{ 'id' => 1, 'name' => 'a' }],
                                                               [{ 'id' => 2, 'name' => 'b' }])

        before_hook('Update', patch: { 'name' => 'x' }, on: new_filter)
        before_hook('Update', patch: { 'name' => 'y' }, on: new_filter)
        after_hook('Update', on: new_filter)

        expect(store.records.map(&:status).uniq).to eq([Recording::PENDING])
      end
    end
  end
end
