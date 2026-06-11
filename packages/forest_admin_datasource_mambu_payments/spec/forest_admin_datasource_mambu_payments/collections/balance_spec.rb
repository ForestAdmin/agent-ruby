module ForestAdminDatasourceMambuPayments
  include ForestAdminDatasourceToolkit::Components::Query

  Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  RSpec.describe Collections::Balance do
    let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client)
    end
    let(:ca_collection) { Collections::ConnectedAccount.new(datasource) }
    let(:collection) { described_class.new(datasource) }

    let(:account) { { 'id' => 'acc1', 'name' => 'Acme' } }
    let(:balance) do
      {
        'id' => 'bal1', 'object' => 'balance',
        'connected_account_id' => 'acc1',
        'type' => 'closing_available', 'direction' => 'credit',
        'amount' => 10_000, 'currency' => 'EUR',
        'date' => '2026-05-11',
        'bank_data' => { 'file_id' => 'f1', 'statement_id' => 's1' },
        'created_at' => '2026-05-11T07:06:09Z'
      }
    end

    before do
      allow(datasource).to receive(:get_collection).with('MambuConnectedAccount').and_return(ca_collection)
    end

    describe 'schema' do
      it 'declares the API-aligned columns' do
        keys = collection.schema[:fields].keys
        expect(keys).to include(
          'id', 'connected_account_id', 'type', 'direction', 'amount', 'currency',
          'date', 'bank_data', 'created_at'
        )
      end

      it 'does not expose the removed as_of_date / updated_at fields' do
        keys = collection.schema[:fields].keys
        expect(keys).not_to include('as_of_date', 'updated_at')
      end

      it 'declares only the connected_account ManyToOne relation' do
        rels = collection.schema[:fields].select do |_, v|
          v.is_a?(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
        end
        expect(rels.keys).to contain_exactly('connected_account')
      end

      it 'leaves `type` as a String column (Numeral has more values than booked/available/expected)' do
        expect(collection.schema[:fields]['type'].column_type).to eq('String')
      end

      it 'does not implement create / update / delete (balances are read-only)' do
        expect(collection.public_methods(false)).not_to include(:create, :update, :delete)
      end
    end

    describe '#list' do
      it 'embeds connected_account when requested by the projection' do
        allow(client).to receive(:list_balances).and_return([balance])
        allow(client).to receive(:find_connected_account).with('acc1').and_return(account)

        rows = collection.list(nil, Filter.new, ['id', 'connected_account:name'])
        expect(rows.first['connected_account']).to include('name' => 'Acme')
      end

      it 'returns the projected columns when no relation is requested' do
        allow(client).to receive(:list_balances).and_return([balance])
        rows = collection.list(nil, Filter.new, %w[id amount currency])
        expect(rows.first).to eq('id' => 'bal1', 'amount' => 10_000, 'currency' => 'EUR')
      end

      it 'short-circuits to find_balance on id lookup' do
        allow(client).to receive(:find_balance).with('bal1').and_return(balance)
        allow(client).to receive(:list_balances)

        filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 'bal1'))
        collection.list(nil, filter, nil)

        expect(client).to have_received(:find_balance).with('bal1')
        expect(client).not_to have_received(:list_balances)
      end
    end

    describe '#aggregate Count' do
      it 'counts via the server-side total' do
        allow(client).to receive(:count_balances).and_return(1)
        result = collection.aggregate(nil, Filter.new, Aggregation.new(operation: 'Count'))
        expect(result.first['value']).to eq(1)
      end
    end
  end
end
