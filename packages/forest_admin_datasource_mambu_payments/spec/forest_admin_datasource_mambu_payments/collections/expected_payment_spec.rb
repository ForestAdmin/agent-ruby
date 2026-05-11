module ForestAdminDatasourceMambuPayments
  include ForestAdminDatasourceToolkit::Components::Query

  Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  RSpec.describe Collections::ExpectedPayment do
    let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client)
    end
    let(:ca_collection) { Collections::ConnectedAccount.new(datasource) }
    let(:ia_collection) { Collections::InternalAccount.new(datasource) }
    let(:ea_collection) { Collections::ExternalAccount.new(datasource) }
    let(:collection) { described_class.new(datasource) }

    let(:account) { { 'id' => 'acc1', 'name' => 'Acme' } }
    let(:expected_payment) do
      {
        'id' => 'ep1', 'object' => 'expected_payment',
        'connected_account_id' => 'acc1',
        'internal_account_id' => 'ia1', 'external_account_id' => 'ea1',
        'type' => 'sepa_credit_transfer', 'direction' => 'credit',
        'status' => 'pending',
        'amount' => 10_000, 'amount_min' => nil, 'amount_max' => nil,
        'currency' => 'EUR',
        'reference' => 'INV-42', 'end_to_end_id' => 'e2e',
        'expected_at' => '2026-06-01',
        'earliest_expected_at' => '2026-05-28', 'latest_expected_at' => '2026-06-05',
        'counterparty' => { 'name' => 'Jane Doe' },
        'matched_amount' => 0, 'matched_payments' => [],
        'custom_fields' => {}, 'metadata' => {},
        'created_at' => '2026-05-11T08:50:28Z'
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
          'id', 'connected_account_id', 'internal_account_id', 'external_account_id',
          'type', 'direction', 'status', 'amount', 'amount_min', 'amount_max', 'currency',
          'reference', 'end_to_end_id', 'expected_at',
          'earliest_expected_at', 'latest_expected_at',
          'counterparty', 'matched_amount', 'matched_payments',
          'custom_fields', 'metadata', 'created_at'
        )
      end

      it 'declares ManyToOne to connected_account, internal_account and external_account' do
        rels = collection.schema[:fields].select do |_, v|
          v.is_a?(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
        end
        expect(rels.keys).to contain_exactly('connected_account', 'internal_account', 'external_account')
      end

      it 'exposes direction as an Enum constrained to debit/credit' do
        f = collection.schema[:fields]
        expect(f['direction'].column_type).to eq('Enum')
        expect(f['direction'].enum_values).to contain_exactly('debit', 'credit')
      end

      it 'marks reconciliation outcome and system-managed fields as read-only' do
        f = collection.schema[:fields]
        %w[id status matched_amount matched_payments created_at].each do |k|
          expect(f[k].is_read_only).to be(true), "#{k} should be read-only"
        end
      end
    end

    describe '#list' do
      it 'returns rows without resolving relations when projection has no relation prefix' do
        allow(client).to receive(:list_expected_payments).and_return([expected_payment])
        allow(client).to receive(:find_connected_account)
        allow(client).to receive(:find_internal_account)
        allow(client).to receive(:find_external_account)

        rows = collection.list(nil, Filter.new, ['id', 'amount'])

        expect(rows).to eq([{ 'id' => 'ep1', 'amount' => 10_000 }])
        expect(client).not_to have_received(:find_connected_account)
      end

      it 'embeds connected_account, internal_account and external_account when requested' do
        allow(client).to receive(:list_expected_payments).and_return([expected_payment])
        allow(client).to receive(:find_connected_account).with('acc1').and_return(account)
        allow(client).to receive(:find_internal_account).with('ia1').and_return('id' => 'ia1')
        allow(client).to receive(:find_external_account).with('ea1').and_return('id' => 'ea1')

        rows = collection.list(nil, Filter.new,
                               ['id', 'connected_account:name', 'internal_account:id', 'external_account:id'])

        expect(rows.first['connected_account']).to include('name' => 'Acme')
        expect(rows.first['internal_account']).to include('id' => 'ia1')
        expect(rows.first['external_account']).to include('id' => 'ea1')
      end

      it 'short-circuits to find_expected_payment on id lookup' do
        allow(client).to receive(:find_expected_payment).with('ep1').and_return(expected_payment)
        allow(client).to receive(:list_expected_payments)

        filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 'ep1'))
        collection.list(nil, filter, nil)

        expect(client).to have_received(:find_expected_payment).with('ep1')
        expect(client).not_to have_received(:list_expected_payments)
      end
    end

    describe '#create' do
      it 'strips system-managed fields before POSTing' do
        allow(client).to receive(:create_expected_payment) do |payload|
          expect(payload).to include('amount' => 10_000, 'direction' => 'credit')
          expect(payload.keys).not_to include('id', 'object', 'status', 'created_at',
                                              'matched_amount', 'matched_payments')
          { 'id' => 'ep1', 'amount' => 10_000 }
        end

        collection.create(nil,
                          'id' => 'ignored', 'object' => 'expected_payment',
                          'status' => 'pending', 'created_at' => 't',
                          'matched_amount' => 0, 'matched_payments' => [],
                          'amount' => 10_000, 'direction' => 'credit')

        expect(client).to have_received(:create_expected_payment)
      end
    end

    describe '#update' do
      it 'PATCHes each id resolved by the filter' do
        allow(client).to receive(:find_expected_payment).with('a').and_return('id' => 'a')
        allow(client).to receive(:find_expected_payment).with('b').and_return('id' => 'b')
        allow(client).to receive(:update_expected_payment)

        collection.update(nil,
                          Filter.new(condition_tree: Leaf.new('id', 'in', %w[a b])),
                          'amount' => 200)

        expect(client).to have_received(:update_expected_payment).with('a', hash_including('amount' => 200))
        expect(client).to have_received(:update_expected_payment).with('b', hash_including('amount' => 200))
      end
    end

    describe '#delete' do
      it 'DELETEs each id resolved by the filter' do
        allow(client).to receive(:find_expected_payment).with('a').and_return('id' => 'a')
        allow(client).to receive(:delete_expected_payment)

        collection.delete(nil, Filter.new(condition_tree: Leaf.new('id', 'equal', 'a')))

        expect(client).to have_received(:delete_expected_payment).with('a')
      end
    end
  end
end
