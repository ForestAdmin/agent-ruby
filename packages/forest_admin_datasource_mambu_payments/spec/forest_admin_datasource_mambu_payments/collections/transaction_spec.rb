module ForestAdminDatasourceMambuPayments
  include ForestAdminDatasourceToolkit::Components::Query

  Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  RSpec.describe Collections::Transaction do
    let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client)
    end
    let(:ca_collection) { Collections::ConnectedAccount.new(datasource) }
    let(:ia_collection) { Collections::InternalAccount.new(datasource) }
    let(:ea_collection) { Collections::ExternalAccount.new(datasource) }
    let(:collection) { described_class.new(datasource) }

    let(:account) { { 'id' => 'acc1', 'name' => 'Acme' } }
    let(:transaction) do
      {
        'id' => 'tx1', 'object' => 'transaction',
        'connected_account_id' => 'acc1',
        'category' => 'direct_debit', 'direction' => 'debit',
        'amount' => 5000, 'currency' => 'EUR',
        'booking_date' => '2026-05-11', 'value_date' => '2026-05-11',
        'description' => 'test', 'structured_reference' => nil,
        'internal_account' => { 'account_number' => '43244675643525' },
        'external_account' => { 'account_number' => 'AG454545' },
        'uetr' => nil, 'reconciliation_status' => 'unreconciled',
        'reconciled_amount' => 0, 'custom_fields' => {},
        'bank_data' => { 'file_id' => 'f1' },
        'created_at' => '2026-05-11T07:10:57Z'
      }
    end

    before do
      allow(datasource).to receive(:get_collection).with('MambuConnectedAccount').and_return(ca_collection)
      allow(datasource).to receive(:get_collection).with('MambuInternalAccount').and_return(ia_collection)
      allow(datasource).to receive(:get_collection).with('MambuExternalAccount').and_return(ea_collection)
    end

    describe 'schema' do
      it 'declares the API-aligned columns' do
        keys = collection.schema[:fields].keys
        expect(keys).to include(
          'id', 'connected_account_id', 'category', 'direction', 'amount', 'currency',
          'description', 'structured_reference', 'value_date', 'booking_date',
          'internal_account_id', 'external_account_id',
          'uetr', 'bank_data', 'reconciliation_status', 'reconciled_amount',
          'custom_fields', 'created_at'
        )
      end

      it 'does not expose the removed counterparty_* / status / payment_order_id fields' do
        keys = collection.schema[:fields].keys
        %w[type counterparty_name counterparty_iban counterparty_bic status payment_order_id end_to_end_id]
          .each { |k| expect(keys).not_to include(k), "schema unexpectedly exposes #{k}" }
      end

      it 'does not expose internal_account_snapshot / external_account_snapshot (replaced by ManyToOne relations)' do
        keys = collection.schema[:fields].keys
        %w[internal_account_snapshot external_account_snapshot].each do |k|
          expect(keys).not_to include(k), "schema unexpectedly exposes #{k}"
        end
      end

      it 'declares ManyToOne to connected_account, internal_account and external_account (no payment_order)' do
        rels = collection.schema[:fields].select do |_, v|
          v.is_a?(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
        end
        expect(rels.keys).to contain_exactly('connected_account', 'internal_account', 'external_account')
      end

      it 'marks every column as read-only (Numeral transactions are immutable)' do
        f = collection.schema[:fields]
        %w[category direction amount currency description bank_data].each do |k|
          expect(f[k].is_read_only).to be(true), "#{k} should be read-only"
        end
      end

      it 'does not implement create / update / delete' do
        # Numeral does not let consumers mutate transactions.
        expect(collection.respond_to?(:create) && collection.method(:create).source_location.nil?).to be_falsey
        expect(collection.public_methods(false)).not_to include(:create, :update, :delete)
      end
    end

    describe '#list' do
      it 'embeds connected_account when requested by the projection' do
        allow(client).to receive(:list_transactions).and_return([transaction])
        allow(client).to receive(:find_connected_account).with('acc1').and_return(account)

        rows = collection.list(nil, Filter.new, ['id', 'connected_account:name'])
        expect(rows.first['connected_account']).to include('name' => 'Acme')
      end

      it 'short-circuits to find_transaction on id lookup' do
        allow(client).to receive(:find_transaction).with('tx1').and_return(transaction)
        allow(client).to receive(:list_transactions)

        filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 'tx1'))
        collection.list(nil, filter, nil)

        expect(client).to have_received(:find_transaction).with('tx1')
        expect(client).not_to have_received(:list_transactions)
      end

      it 'projects to the requested column subset' do
        allow(client).to receive(:list_transactions).and_return([transaction])
        rows = collection.list(nil, Filter.new, %w[id category amount])
        expect(rows.first).to eq('id' => 'tx1', 'category' => 'direct_debit', 'amount' => 5000)
      end
    end

    describe '#aggregate Count' do
      it 'counts via the server-side total' do
        allow(client).to receive(:count_transactions).and_return(2)
        result = collection.aggregate(nil, Filter.new, Aggregation.new(operation: 'Count'))
        expect(result.first['value']).to eq(2)
      end
    end
  end
end
