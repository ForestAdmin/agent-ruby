module ForestAdminDatasourceMambuPayments
  include ForestAdminDatasourceToolkit::Components::Query

  Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  RSpec.describe Collections::AccountHolder do
    let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client)
    end
    let(:collection) { described_class.new(datasource) }

    let(:holder) do
      {
        'id' => '019e1655-bfa8-75bc-b5b8-06c144903273',
        'object' => 'account_holder',
        'name' => 'Account Holder Test Christophe',
        'metadata' => {},
        'created_at' => '2026-05-11T09:19:38Z',
        'disabled_at' => nil
      }
    end

    describe 'schema' do
      it 'declares the 6 API-aligned columns and the two OneToMany inverses' do
        expect(collection.schema[:fields].keys).to contain_exactly(
          'id', 'object', 'name', 'metadata', 'disabled_at', 'created_at',
          'external_accounts', 'internal_accounts'
        )
      end

      it 'exposes external_accounts and internal_accounts as OneToMany relations' do
        f = collection.schema[:fields]
        expect(f['external_accounts']).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema)
        expect(f['internal_accounts']).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema)
      end

      it 'marks system-managed fields read-only' do
        f = collection.schema[:fields]
        %w[id object disabled_at created_at].each { |k| expect(f[k].is_read_only).to be(true) }
      end

      it 'leaves name and metadata writable' do
        f = collection.schema[:fields]
        expect(f['name'].is_read_only).to be(false)
        expect(f['metadata'].is_read_only).to be(false)
      end
    end

    describe '#serialize' do
      it 'maps the API record to a flat hash' do
        expect(collection.serialize(holder)).to include(
          'id' => holder['id'], 'name' => holder['name'], 'metadata' => {}
        )
      end
    end

    describe '#list' do
      it 'short-circuits to find_account_holder on id lookup' do
        allow(client).to receive(:find_account_holder).with(holder['id']).and_return(holder)
        allow(client).to receive(:list_account_holders)

        filter = Filter.new(condition_tree: Leaf.new('id', 'equal', holder['id']))
        rows = collection.list(nil, filter, nil)

        expect(rows.first['name']).to eq(holder['name'])
        expect(client).not_to have_received(:list_account_holders)
      end

      it 'falls back to a paginated list when there is no id filter' do
        allow(client).to receive(:list_account_holders).and_return([holder])

        rows = collection.list(nil, Filter.new, %w[id name])

        expect(rows).to eq([{ 'id' => holder['id'], 'name' => holder['name'] }])
        expect(client).to have_received(:list_account_holders).with(page: 1, limit: Client::MAX_PER_PAGE)
      end
    end

    describe '#aggregate Count' do
      it 'counts via the server-side total' do
        allow(client).to receive(:count_account_holders).and_return(2)
        result = collection.aggregate(nil, Filter.new, Aggregation.new(operation: 'Count'))
        expect(result.first['value']).to eq(2)
      end
    end

    describe '#create' do
      it 'POSTs the payload stripping system-managed fields' do
        allow(client).to receive(:create_account_holder) do |payload|
          expect(payload).to include('name' => 'New')
          expect(payload.keys).not_to include('id', 'object', 'created_at', 'disabled_at')
          { 'id' => 'new', 'name' => 'New' }
        end

        result = collection.create(nil,
                                   'id' => 'ignored', 'object' => 'account_holder',
                                   'created_at' => 't', 'disabled_at' => nil,
                                   'name' => 'New')
        expect(result['id']).to eq('new')
      end
    end

    describe '#update' do
      it 'PATCHes every id resolved by the filter' do
        allow(client).to receive(:find_account_holder).with('a').and_return('id' => 'a')
        allow(client).to receive(:find_account_holder).with('b').and_return('id' => 'b')
        allow(client).to receive(:update_account_holder)

        collection.update(nil,
                          Filter.new(condition_tree: Leaf.new('id', 'in', %w[a b])),
                          'name' => 'Renamed')

        expect(client).to have_received(:update_account_holder).with('a', hash_including('name' => 'Renamed'))
        expect(client).to have_received(:update_account_holder).with('b', hash_including('name' => 'Renamed'))
      end
    end

    describe '#delete' do
      it 'DELETEs every id resolved by the filter' do
        allow(client).to receive(:find_account_holder).with('a').and_return('id' => 'a')
        allow(client).to receive(:delete_account_holder)

        collection.delete(nil, Filter.new(condition_tree: Leaf.new('id', 'equal', 'a')))

        expect(client).to have_received(:delete_account_holder).with('a')
      end
    end
  end
end
