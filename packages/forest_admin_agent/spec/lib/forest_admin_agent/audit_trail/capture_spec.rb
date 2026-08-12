require 'spec_helper'

module ForestAdminAgent
  module AuditTrail
    describe Capture do
      let(:column_schema) { ForestAdminDatasourceToolkit::Schema::ColumnSchema }

      let(:store) do
        Class.new do
          attr_reader :records

          def initialize
            @records = []
          end

          def append(record)
            @records << record
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
      let(:collection) { double('collection') }
      let(:caller_double) { double('caller', id: 42, request_id: 'req-xyz') }

      # What a hook context really hands out: the caller is already bound, so `list` takes
      # (filter, projection). A verifying double keeps that contract honest.
      let(:relaxed_collection) do
        instance_double(ForestAdminDatasourceCustomizer::Context::RelaxedWrappers::RelaxedCollection)
      end

      let(:registrations) { [] }
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

      # execute_after stops at the first exception, so being last would mean losing the record of a write
      # that already happened whenever another customization raises in its own after hook.
      it 'registers its after hooks ahead of the ones already there, and its before hooks after them' do
        expect(registrations).to contain_exactly(
          ['After', 'Create', true], ['Before', 'Update', false], ['After', 'Update', true],
          ['Before', 'Delete', false], ['After', 'Delete', true]
        )
      end

      it 'records a create with only the writable columns' do
        record = { 'id' => 1, 'name' => 'Acme', 'address' => { 'city' => 'Paris' } }

        hooks['After_Create'].call(double('ctx', caller: caller_double, record: record))

        audit = store.records.last
        expect(audit.operation).to eq('create')
        expect(audit.record_id).to eq('1')
        expect(audit.user_id).to eq(42)
        expect(audit.correlation_key).to eq('req-xyz')
        expect(audit.previous_values).to eq({})
        expect(audit.new_values).to eq({ 'name' => 'Acme', 'address' => { 'city' => 'Paris' } })
      end

      def before_hook(type, patch: nil)
        hooks["Before_#{type}"].call(
          double('before', caller: caller_double, filter: Object.new,
                           collection: relaxed_collection, patch: patch)
        )
      end

      def after_hook(type)
        hooks["After_#{type}"].call(double('after', caller: caller_double, filter: Object.new))
      end

      it "shares the caller's request id as the correlation key across records of one operation" do
        allow(relaxed_collection).to receive(:list).and_return(
          [{ 'id' => 1, 'name' => 'A' }, { 'id' => 2, 'name' => 'B' }]
        )

        before_hook('Update', patch: { 'name' => 'Z' })
        after_hook('Update')

        expect(store.records.map(&:correlation_key)).to eq(%w[req-xyz req-xyz])
      end

      it 'records an update with the minimal nested diff' do
        before_record = { 'id' => 1, 'name' => 'Acme', 'address' => { 'city' => 'Paris', 'zip' => '1' } }
        allow(relaxed_collection).to receive(:list).and_return([before_record])

        before_hook('Update', patch: { 'address' => { 'city' => 'Lyon', 'zip' => '1' } })
        after_hook('Update')

        audit = store.records.last
        expect(audit.operation).to eq('update')
        expect(audit.previous_values).to eq({ 'address' => { 'city' => 'Paris' } })
        expect(audit.new_values).to eq({ 'address' => { 'city' => 'Lyon' } })
      end

      it 'does not record an update when nothing writable changed' do
        allow(relaxed_collection).to receive(:list).and_return([{ 'id' => 1, 'name' => 'Acme' }])

        before_hook('Update', patch: { 'name' => 'Acme' })
        after_hook('Update')

        expect(store.records).to be_empty
      end

      # The before and after hooks are handed different filter objects (the after context always
      # carries the caller's original), so pairing must not depend on that object.
      it 'pairs the snapshot with its after hook without relying on the filter object' do
        allow(relaxed_collection).to receive(:list).and_return([{ 'id' => 1, 'name' => 'Acme' }])

        before_hook('Update', patch: { 'name' => 'Effective' })
        after_hook('Update')

        expect(store.records.last.new_values).to eq({ 'name' => 'Effective' })
      end

      it 'still audits the next write after one raised between its hooks' do
        allow(relaxed_collection).to receive(:list).and_return([{ 'id' => 1, 'name' => 'Acme' }])

        before_hook('Update', patch: { 'name' => 'Never written' })
        before_hook('Update', patch: { 'name' => 'Z' })
        after_hook('Update')

        expect(store.records.map { |record| record.new_values['name'] }).to eq(['Z'])
      end

      it 'drops the oldest stranded snapshots instead of growing the thread-local without bound' do
        allow(relaxed_collection).to receive(:list).and_return([{ 'id' => 1, 'name' => 'Acme' }])

        (described_class::MAX_SNAPSHOTS + 4).times { before_hook('Update', patch: { 'name' => 'stranded' }) }
        before_hook('Update', patch: { 'name' => 'Z' })
        after_hook('Update')

        expect(Thread.current[:forest_audit_trail_snapshots].size).to eq(described_class::MAX_SNAPSHOTS - 1)
        expect(store.records.map { |record| record.new_values['name'] }).to eq(['Z'])
      end

      it 'records a delete with the previous values' do
        allow(relaxed_collection).to receive(:list).and_return([{ 'id' => 7, 'name' => 'Gone', 'address' => nil }])

        before_hook('Delete')
        after_hook('Delete')

        audit = store.records.last
        expect(audit.operation).to eq('delete')
        expect(audit.record_id).to eq('7')
        expect(audit.previous_values).to eq({ 'name' => 'Gone', 'address' => nil })
        expect(audit.new_values).to eq({})
      end

      # The write already happened when the after hook runs, so a broken audit database must not turn a
      # successful change into a client-visible error.
      it 'logs and swallows a store failure instead of failing the write' do
        logger = instance_spy(Services::LoggerService)
        allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
        allow(store).to receive(:append).and_raise(StandardError, 'audit db is down')

        expect do
          hooks['After_Create'].call(double('ctx', caller: caller_double, record: { 'id' => 1, 'name' => 'Acme' }))
        end.not_to raise_error
        expect(logger).to have_received(:log).with('Error', /audit db is down/)
      end

      it 'does not block the write when the before-hook snapshot cannot be read' do
        logger = instance_spy(Services::LoggerService)
        allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
        allow(relaxed_collection).to receive(:list).and_raise(StandardError, 'read failed')

        expect do
          before_hook('Update', patch: { 'name' => 'Z' })
          after_hook('Update')
        end.not_to raise_error
        expect(store.records).to be_empty
      end

      it 'masks redacted fields while still recording the change' do
        described_class.new.run(datasource_customizer, nil, store: store, redact: { 'companies' => ['name'] })

        hooks['After_Create'].call(
          double('ctx', caller: caller_double, record: { 'id' => 1, 'name' => 'Secret', 'address' => nil })
        )

        expect(store.records.last.new_values['name']).to eq(described_class::REDACTED)
      end
    end
  end
end
