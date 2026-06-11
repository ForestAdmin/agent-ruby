module ForestAdminDatasourceMambuPayments
  include ForestAdminDatasourceToolkit::Components::Query

  Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  RSpec.describe Collections::ConnectedAccount do
    let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
    let(:datasource) { instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client) }
    let(:collection) { described_class.new(datasource) }

    let(:account) do
      {
        'id' => 'b6425af8', 'object' => 'connected_account',
        'name' => 'SEPA Indirect', 'type' => 'financial_institution',
        'bank_id' => 'numbank', 'bank_code' => 'BIC', 'bank_name' => 'Bank',
        'currency' => 'EUR', 'services_activated' => %w[sct sdd],
        'file_auto_approval' => true,
        'created_at' => '2026-05-04T08:35:01Z'
      }
    end

    describe 'schema' do
      it 'declares the API-aligned column fields' do
        keys = collection.schema[:fields].keys
        expect(keys).to include(
          'id', 'name', 'type', 'bank_id', 'bank_code', 'bank_name',
          'bank_address', 'address', 'services_activated', 'metadata',
          'file_auto_approval', 'disabled_at', 'created_at'
        )
      end

      it 'does not expose fictitious fields removed in the alignment pass' do
        keys = collection.schema[:fields].keys
        %w[holder_name iban bic status service partner_account_id balance_cents].each do |k|
          expect(keys).not_to include(k), "schema unexpectedly exposes #{k}"
        end
      end

      it 'declares OneToMany relations to transactions, payment_orders and balances' do
        f = collection.schema[:fields]
        %w[transactions payment_orders balances].each do |name|
          expect(f[name]).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema)
        end
      end

      it 'marks every column as read-only (Numeral has no POST/PATCH/DELETE on /connected_accounts)' do
        f = collection.schema[:fields].reject do |_, v|
          v.is_a?(ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema)
        end
        f.each do |name, schema|
          expect(schema.is_read_only).to be(true), "#{name} should be read-only"
        end
      end

      it 'does not implement create / update / delete' do
        expect(collection.public_methods(false)).not_to include(:create, :update, :delete)
      end
    end

    describe '#serialize' do
      it 'maps the API record to a flat hash with the schema fields' do
        result = collection.serialize(account)
        expect(result).to include('id' => 'b6425af8', 'name' => 'SEPA Indirect',
                                  'services_activated' => %w[sct sdd],
                                  'file_auto_approval' => true)
      end
    end

    describe '#list' do
      it 'short-circuits to find_connected_account on id lookup' do
        allow(client).to receive(:find_connected_account).with('b6425af8').and_return(account)
        allow(client).to receive(:list_connected_accounts)

        filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 'b6425af8'))
        rows = collection.list(nil, filter, nil)

        expect(rows.first['id']).to eq('b6425af8')
        expect(client).not_to have_received(:list_connected_accounts)
      end

      it 'falls back to a paginated list when there is no id filter' do
        allow(client).to receive(:list_connected_accounts).and_return([account])

        rows = collection.list(nil, Filter.new, ['id', 'name'])

        expect(rows).to eq([{ 'id' => 'b6425af8', 'name' => 'SEPA Indirect' }])
        expect(client).to have_received(:list_connected_accounts).with(limit: Client::MAX_PER_PAGE)
      end

      it 'drops 404 (nil) records from the result' do
        allow(client).to receive(:find_connected_account).and_return(nil)
        filter = Filter.new(condition_tree: Leaf.new('id', 'in', %w[missing]))
        expect(collection.list(nil, filter, nil)).to eq([])
      end
    end

    describe '#aggregate Count' do
      it 'counts via the server-side total' do
        allow(client).to receive(:count_connected_accounts).and_return(2)
        result = collection.aggregate(nil, Filter.new, Aggregation.new(operation: 'Count'))
        expect(result.first['value']).to eq(2)
      end
    end
  end
end
