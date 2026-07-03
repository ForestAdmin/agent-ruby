require 'spec_helper'

module ForestAdminAuditTrail
  describe Plugin do
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

    let(:collection_customizer) do
      customizer = double('CollectionCustomizer', name: 'companies', collection: collection)
      allow(customizer).to receive(:add_hook) { |position, type, &block| hooks["#{position}_#{type}"] = block }
      customizer
    end

    before do
      allow(collection).to receive(:schema).and_return({ fields: fields })
      described_class.new.run(nil, collection_customizer, store: store)
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

    it "shares the caller's request id as the correlation key across records of one operation" do
      filter = Object.new
      allow(collection).to receive(:list).and_return(
        [{ 'id' => 1, 'name' => 'A' }, { 'id' => 2, 'name' => 'B' }]
      )

      hooks['Before_Update'].call(double('before', caller: caller_double, filter: filter, collection: collection))
      hooks['After_Update'].call(double('after', caller: caller_double, filter: filter, patch: { 'name' => 'Z' }))

      expect(store.records.map(&:correlation_key)).to eq(%w[req-xyz req-xyz])
    end

    it 'records an update with the minimal nested diff' do
      filter = Object.new
      before_record = { 'id' => 1, 'name' => 'Acme', 'address' => { 'city' => 'Paris', 'zip' => '1' } }
      allow(collection).to receive(:list).and_return([before_record])

      hooks['Before_Update'].call(double('before', caller: caller_double, filter: filter, collection: collection))
      hooks['After_Update'].call(
        double('after', caller: caller_double, filter: filter,
                        patch: { 'address' => { 'city' => 'Lyon', 'zip' => '1' } })
      )

      audit = store.records.last
      expect(audit.operation).to eq('update')
      expect(audit.previous_values).to eq({ 'address' => { 'city' => 'Paris' } })
      expect(audit.new_values).to eq({ 'address' => { 'city' => 'Lyon' } })
    end

    it 'does not record an update when nothing writable changed' do
      filter = Object.new
      allow(collection).to receive(:list).and_return([{ 'id' => 1, 'name' => 'Acme' }])

      hooks['Before_Update'].call(double('before', caller: caller_double, filter: filter, collection: collection))
      hooks['After_Update'].call(double('after', caller: caller_double, filter: filter, patch: { 'name' => 'Acme' }))

      expect(store.records).to be_empty
    end

    it 'records a delete with the previous values' do
      filter = Object.new
      allow(collection).to receive(:list).and_return([{ 'id' => 7, 'name' => 'Gone', 'address' => nil }])

      hooks['Before_Delete'].call(double('before', caller: caller_double, filter: filter, collection: collection))
      hooks['After_Delete'].call(double('after', caller: caller_double, filter: filter))

      audit = store.records.last
      expect(audit.operation).to eq('delete')
      expect(audit.record_id).to eq('7')
      expect(audit.previous_values).to eq({ 'name' => 'Gone', 'address' => nil })
      expect(audit.new_values).to eq({})
    end

    it 'masks redacted fields while still recording the change' do
      described_class.new.run(nil, collection_customizer, store: store, redact: { 'companies' => ['name'] })

      hooks['After_Create'].call(
        double('ctx', caller: caller_double, record: { 'id' => 1, 'name' => 'Secret', 'address' => nil })
      )

      expect(store.records.last.new_values['name']).to eq(described_class::REDACTED)
    end
  end
end
