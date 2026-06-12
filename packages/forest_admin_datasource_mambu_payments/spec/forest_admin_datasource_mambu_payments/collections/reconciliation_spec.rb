module ForestAdminDatasourceMambuPayments
  include ForestAdminDatasourceToolkit::Components::Query

  Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  RSpec.describe Collections::Reconciliation do
    let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client)
    end
    let(:tx_collection) { Collections::Transaction.new(datasource) }
    let(:collection) { described_class.new(datasource) }

    let(:transaction) { { 'id' => 'tx1', 'amount' => 3000 } }
    let(:reconciliation) do
      {
        'id' => 'rec1', 'object' => 'reconciliation',
        'transaction_id' => 'tx1',
        'payment_id' => 'po1', 'payment_type' => 'payment_order',
        'amount' => 3000, 'match_type' => 'manual',
        'metadata' => { 'note' => 'manual match' },
        'canceled_at' => nil,
        'created_at' => '2026-05-20T08:00:00Z'
      }
    end

    before do
      allow(datasource).to receive(:get_collection).with('MambuTransaction').and_return(tx_collection)
    end

    describe 'schema' do
      it 'declares the API-aligned columns' do
        keys = collection.schema[:fields].keys
        expect(keys).to include(
          'id', 'object', 'transaction_id', 'payment_id', 'payment_type',
          'amount', 'match_type', 'metadata', 'canceled_at', 'created_at'
        )
      end

      it 'declares a ManyToOne relation to transaction via transaction_id' do
        rel = collection.schema[:fields]['transaction']
        expect(rel).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
        expect(rel.foreign_key).to eq('transaction_id')
        expect(rel.foreign_key_target).to eq('id')
      end

      it 'does not expose a typed relation for payment_id (polymorphic in Numeral)' do
        rels = collection.schema[:fields].select do |_, v|
          v.is_a?(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
        end
        expect(rels.keys).to contain_exactly('transaction')
      end

      it 'exposes payment_type and match_type as Enum columns with Numeral values' do
        f = collection.schema[:fields]
        expect(f['payment_type'].column_type).to eq('Enum')
        expect(f['payment_type'].enum_values).to contain_exactly(
          'payment_order', 'incoming_payment', 'return', 'expected_payment', 'payment_capture'
        )
        expect(f['match_type'].column_type).to eq('Enum')
        expect(f['match_type'].enum_values).to contain_exactly('manual', 'auto')
      end

      it 'marks system-managed columns as read-only' do
        f = collection.schema[:fields]
        %w[id object payment_type match_type canceled_at created_at].each do |k|
          expect(f[k].is_read_only).to be(true), "#{k} should be read-only"
        end
      end

      it 'keeps transaction_id, payment_id, amount and metadata writable on create' do
        f = collection.schema[:fields]
        %w[transaction_id payment_id amount metadata].each do |k|
          expect(f[k].is_read_only).to be(false), "#{k} should be writable"
        end
      end

      it 'does not implement delete (Numeral has no DELETE on /reconciliations)' do
        expect(collection.public_methods(false)).not_to include(:delete)
      end
    end

    describe '#serialize' do
      it 'maps the API record to a flat hash with the schema fields' do
        result = collection.serialize(reconciliation)
        expect(result).to include(
          'id' => 'rec1', 'transaction_id' => 'tx1',
          'payment_id' => 'po1', 'payment_type' => 'payment_order',
          'amount' => 3000, 'match_type' => 'manual'
        )
      end
    end

    describe '#list' do
      it 'returns rows without resolving the relation when projection has no relation prefix' do
        allow(client).to receive(:list_reconciliations).and_return([reconciliation])
        allow(client).to receive(:find_transaction)

        rows = collection.list(nil, Filter.new, ['id', 'transaction_id'])

        expect(rows).to eq([{ 'id' => 'rec1', 'transaction_id' => 'tx1' }])
        expect(client).not_to have_received(:find_transaction)
      end

      it 'embeds transaction when the projection asks for it' do
        allow(client).to receive(:list_reconciliations).and_return([reconciliation])
        allow(client).to receive(:find_transaction).with('tx1').and_return(transaction)

        rows = collection.list(nil, Filter.new, ['id', 'transaction:id'])

        expect(rows.first['transaction']).to include('id' => 'tx1')
      end

      it 'short-circuits to find_reconciliation on id lookup' do
        allow(client).to receive(:find_reconciliation).with('rec1').and_return(reconciliation)
        allow(client).to receive(:list_reconciliations)

        filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 'rec1'))
        collection.list(nil, filter, nil)

        expect(client).to have_received(:find_reconciliation).with('rec1')
        expect(client).not_to have_received(:list_reconciliations)
      end

      it 'drops 404 (nil) records from the result on id lookup' do
        allow(client).to receive(:find_reconciliation).and_return(nil)
        filter = Filter.new(condition_tree: Leaf.new('id', 'in', %w[missing]))
        expect(collection.list(nil, filter, nil)).to eq([])
      end

      it 'forwards a translated transaction_id filter to the API' do
        allow(client).to receive(:list_reconciliations).and_return([])

        filter = Filter.new(condition_tree: Leaf.new('transaction_id', 'equal', 'tx1'))
        collection.list(nil, filter, ['id'])

        expect(client).to have_received(:list_reconciliations)
          .with(hash_including('transaction_id' => 'tx1'))
      end

      it 'forwards payment_id, payment_type and match_type filters to the API' do
        allow(client).to receive(:list_reconciliations).and_return([])

        filter = Filter.new(condition_tree: Leaf.new('match_type', 'equal', 'auto'))
        collection.list(nil, filter, ['id'])

        expect(client).to have_received(:list_reconciliations).with(hash_including('match_type' => 'auto'))
      end

      it 'raises a clear error on an undeclared filter rather than silently dropping it' do
        allow(client).to receive(:list_reconciliations)

        filter = Filter.new(condition_tree: Leaf.new('amount', 'equal', 3000))

        expect { collection.list(nil, filter, ['id']) }
          .to raise_error(UnsupportedOperatorError, /'amount'/)
        expect(client).not_to have_received(:list_reconciliations)
      end
    end

    describe '#create' do
      it 'POSTs the payload stripping system-managed fields' do
        allow(client).to receive(:create_reconciliation) do |payload|
          expect(payload).to include('transaction_id' => 'tx1', 'payment_id' => 'po1', 'amount' => 3000)
          expect(payload.keys).not_to include('id', 'object', 'match_type', 'canceled_at', 'created_at')
          { 'id' => 'rec1', 'transaction_id' => 'tx1', 'payment_id' => 'po1' }
        end

        result = collection.create(nil,
                                   'id' => 'ignored', 'object' => 'reconciliation',
                                   'transaction_id' => 'tx1', 'payment_id' => 'po1',
                                   'amount' => 3000,
                                   'match_type' => 'auto', 'canceled_at' => 't',
                                   'created_at' => 't',
                                   'metadata' => { 'src' => 'qa' })
        expect(result['id']).to eq('rec1')
      end
    end

    describe '#update' do
      it 'PATCHes each id resolved by the filter with the writable subset only' do
        allow(client).to receive(:find_reconciliation).with('a').and_return('id' => 'a')
        allow(client).to receive(:find_reconciliation).with('b').and_return('id' => 'b')
        allow(client).to receive(:update_reconciliation)

        collection.update(nil,
                          Filter.new(condition_tree: Leaf.new('id', 'in', %w[a b])),
                          'metadata' => { 'note' => 'updated' },
                          'created_at' => 'ignored',
                          'match_type' => 'ignored')

        %w[a b].each do |id|
          expect(client).to have_received(:update_reconciliation)
            .with(id, hash_including('metadata' => { 'note' => 'updated' }))
          expect(client).to have_received(:update_reconciliation)
            .with(id, hash_excluding('created_at', 'match_type'))
        end
      end
    end
  end
end
