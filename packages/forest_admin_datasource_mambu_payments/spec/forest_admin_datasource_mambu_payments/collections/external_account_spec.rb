module ForestAdminDatasourceMambuPayments
  include ForestAdminDatasourceToolkit::Components::Query

  Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  RSpec.describe Collections::ExternalAccount do
    let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client)
    end
    let(:ah_collection) { Collections::AccountHolder.new(datasource) }
    let(:collection) { described_class.new(datasource) }

    let(:holder) { { 'id' => 'ah1', 'name' => 'Christophe' } }
    let(:external_account) do
      {
        'id' => '019e16fb', 'object' => 'external_account',
        'type' => 'individual', 'status' => 'approved',
        'name' => 'ext acc', 'holder_name' => 'Christophe',
        'holder_address' => { 'country' => '' },
        'account_number' => 'EZR341234213', 'bank_code' => 'erez',
        'account_holder_id' => 'ah1',
        'created_at' => '2026-05-11T12:20:17Z', 'disabled_at' => nil
      }
    end

    before do
      allow(datasource).to receive(:get_collection).with('MambuAccountHolder').and_return(ah_collection)
    end

    describe 'schema' do
      it 'declares the main API columns and the account_holder relation' do
        keys = collection.schema[:fields].keys
        expect(keys).to include(
          'id', 'object', 'type', 'status', 'name', 'holder_name', 'holder_address',
          'account_number', 'bank_code', 'account_holder_id',
          'company_registration_number', 'metadata', 'custom_fields',
          'account_verification', 'created_at', 'disabled_at'
        )
        expect(collection.schema[:fields]['account_holder'])
          .to be_a(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
      end

      it 'marks status, status_details and account_verification read-only (Numeral-managed)' do
        f = collection.schema[:fields]
        %w[status status_details account_verification].each do |k|
          expect(f[k].is_read_only).to be(true), "#{k} should be read-only"
        end
      end
    end

    describe '#list' do
      it 'embeds account_holder when requested by the projection' do
        allow(client).to receive(:list_external_accounts).and_return([external_account])
        allow(client).to receive(:find_account_holder).with('ah1').and_return(holder)

        rows = collection.list(nil, Filter.new, ['id', 'account_holder:name'])
        expect(rows.first['account_holder']).to include('name' => 'Christophe')
      end

      it 'short-circuits to find_external_account on id lookup' do
        allow(client).to receive(:find_external_account).with('019e16fb').and_return(external_account)
        allow(client).to receive(:list_external_accounts)

        filter = Filter.new(condition_tree: Leaf.new('id', 'equal', '019e16fb'))
        collection.list(nil, filter, nil)

        expect(client).to have_received(:find_external_account).with('019e16fb')
        expect(client).not_to have_received(:list_external_accounts)
      end
    end

    describe '#create' do
      it 'POSTs the payload stripping system-managed fields' do
        allow(client).to receive(:create_external_account) do |payload|
          expect(payload).to include('name' => 'New')
          expect(payload.keys).not_to include('id', 'object', 'status', 'status_details',
                                              'created_at', 'disabled_at', 'account_verification')
          { 'id' => 'new', 'name' => 'New' }
        end

        collection.create(nil,
                          'id' => 'ignored', 'object' => 'external_account',
                          'status' => 'approved', 'status_details' => '',
                          'created_at' => 't', 'disabled_at' => nil,
                          'account_verification' => {}, 'name' => 'New')

        expect(client).to have_received(:create_external_account)
      end
    end

    describe '#update' do
      it 'PATCHes each id resolved by the filter' do
        allow(client).to receive(:find_external_account).with('a').and_return('id' => 'a')
        allow(client).to receive(:update_external_account)

        collection.update(nil,
                          Filter.new(condition_tree: Leaf.new('id', 'equal', 'a')),
                          'name' => 'Renamed')

        expect(client).to have_received(:update_external_account).with('a', hash_including('name' => 'Renamed'))
      end
    end

    describe '#delete' do
      it 'DELETEs each id resolved by the filter' do
        allow(client).to receive(:find_external_account).with('a').and_return('id' => 'a')
        allow(client).to receive(:delete_external_account)

        collection.delete(nil, Filter.new(condition_tree: Leaf.new('id', 'equal', 'a')))

        expect(client).to have_received(:delete_external_account).with('a')
      end
    end
  end
end
