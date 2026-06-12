module ForestAdminDatasourceMambuPayments
  include ForestAdminDatasourceToolkit::Components::Query

  Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  RSpec.describe Collections::InternalAccount do
    let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client)
    end
    let(:ah_collection) { Collections::AccountHolder.new(datasource) }
    let(:collection) { described_class.new(datasource) }

    let(:holder) { { 'id' => 'ah1', 'name' => 'Christophe' } }
    let(:internal_account) do
      {
        'id' => '019e1671', 'object' => 'internal_account',
        'status' => 'active', 'type' => 'own',
        'name' => 'Internal Account Test', 'holder_name' => 'Christophe',
        'connected_account_ids' => ['b6425af8'],
        'account_number' => 'AZ342544', 'bank_code' => 'TRE3635467',
        'account_holder_id' => 'ah1',
        'currencies' => ['EUR'], 'synchronized_with_bank' => false,
        'created_at' => '2026-05-11T09:50:06Z'
      }
    end

    before do
      allow(datasource).to receive(:get_collection).with('MambuAccountHolder').and_return(ah_collection)
    end

    describe 'schema' do
      it 'declares the main API columns including connected_account_ids as Json' do
        keys = collection.schema[:fields].keys
        expect(keys).to include(
          'id', 'object', 'status', 'type', 'name', 'holder_name',
          'connected_account_ids', 'account_number', 'bank_code',
          'account_holder_id', 'currencies', 'synchronized_with_bank',
          'cbs_account_id', 'distinguished_name', 'metadata', 'bank_data', 'created_at'
        )
        expect(collection.schema[:fields]['connected_account_ids'].column_type).to eq('Json')
      end

      it 'declares synchronized_with_bank as a Boolean column' do
        expect(collection.schema[:fields]['synchronized_with_bank'].column_type).to eq('Boolean')
      end

      it 'declares the account_holder ManyToOne relation' do
        expect(collection.schema[:fields]['account_holder'])
          .to be_a(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
      end
    end

    describe '#list' do
      it 'embeds account_holder when requested by the projection' do
        allow(client).to receive(:list_internal_accounts).and_return([internal_account])
        allow(client).to receive(:find_account_holder).with('ah1').and_return(holder)

        rows = collection.list(nil, Filter.new, ['id', 'account_holder:name'])
        expect(rows.first['account_holder']).to include('name' => 'Christophe')
      end

      it 'short-circuits to find_internal_account on id lookup' do
        allow(client).to receive(:find_internal_account).with('019e1671').and_return(internal_account)
        allow(client).to receive(:list_internal_accounts)

        filter = Filter.new(condition_tree: Leaf.new('id', 'equal', '019e1671'))
        collection.list(nil, filter, nil)

        expect(client).to have_received(:find_internal_account).with('019e1671')
        expect(client).not_to have_received(:list_internal_accounts)
      end
    end

    describe '#create' do
      it 'POSTs the payload stripping system-managed fields' do
        allow(client).to receive(:create_internal_account) do |payload|
          expect(payload).to include('name' => 'New')
          expect(payload.keys).not_to include('id', 'object', 'status', 'status_details', 'created_at', 'bank_data')
          { 'id' => 'new', 'name' => 'New' }
        end

        collection.create(nil,
                          'id' => 'ignored', 'object' => 'internal_account',
                          'status' => 'active', 'status_details' => '',
                          'created_at' => 't', 'bank_data' => {}, 'name' => 'New')

        expect(client).to have_received(:create_internal_account)
      end
    end

    describe '#update' do
      it 'PATCHes each id resolved by the filter' do
        allow(client).to receive(:find_internal_account).with('a').and_return('id' => 'a')
        allow(client).to receive(:update_internal_account)

        collection.update(nil,
                          Filter.new(condition_tree: Leaf.new('id', 'equal', 'a')),
                          'name' => 'Renamed')

        expect(client).to have_received(:update_internal_account).with('a', hash_including('name' => 'Renamed'))
      end
    end

    describe '#delete' do
      it 'DELETEs each id resolved by the filter' do
        allow(client).to receive(:find_internal_account).with('a').and_return('id' => 'a')
        allow(client).to receive(:delete_internal_account)

        collection.delete(nil, Filter.new(condition_tree: Leaf.new('id', 'equal', 'a')))

        expect(client).to have_received(:delete_internal_account).with('a')
      end
    end
  end
end
