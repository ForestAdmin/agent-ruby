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
        'id' => '019e17e6-bac7-7607-9d91-12147d8db4c8',
        'idempotency_key' => '',
        'object' => 'expected_payment',
        'direction' => 'debit',
        'amount_from' => 5000, 'amount_to' => 6000,
        'currency' => 'EUR',
        'start_date' => '2026-05-11', 'end_date' => '2026-05-11',
        'connected_account_id' => '456d2975-d58b-4a90-89b8-efcc3239c866',
        'external_account' => { 'account_number' => 'AG454545', 'holder_name' => 'test external account' },
        'external_account_id' => '',
        'internal_account' => { 'account_number' => '43244675643525' },
        'internal_account_id' => '',
        'reconciliation_status' => 'unreconciled',
        'reconciled_amount' => 0,
        'metadata' => {}, 'custom_fields' => {},
        'descriptions' => ['test expected payment'],
        'created_at' => '2026-05-11T16:37:37.612847Z',
        'updated_at' => '2026-05-11T16:37:37.612855Z',
        'canceled_at' => nil
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
          'id', 'object', 'idempotency_key',
          'connected_account_id', 'internal_account_id', 'external_account_id',
          'direction', 'amount_from', 'amount_to', 'currency',
          'start_date', 'end_date', 'descriptions',
          'reconciliation_status', 'reconciled_amount',
          'custom_fields', 'metadata',
          'created_at', 'updated_at', 'canceled_at'
        )
      end

      it 'does not expose fields that are absent from the Numeral payload' do
        keys = collection.schema[:fields].keys
        # The account data is exposed through the ManyToOne relations, not as
        # embedded snapshot columns (single source of truth, like Transaction).
        %w[amount amount_min amount_max status type reference end_to_end_id
           expected_at earliest_expected_at latest_expected_at
           counterparty matched_amount matched_payments
           internal_account_snapshot external_account_snapshot].each do |k|
          expect(keys).not_to include(k), "schema unexpectedly exposes #{k}"
        end
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

      it 'keeps descriptions as Json' do
        f = collection.schema[:fields]
        expect(f['descriptions'].column_type).to eq('Json')
      end

      it 'marks reconciliation outcome and timestamps as read-only' do
        f = collection.schema[:fields]
        %w[id object reconciliation_status reconciled_amount
           created_at updated_at canceled_at].each do |k|
          expect(f[k].is_read_only).to be(true), "#{k} should be read-only"
        end
      end
    end

    describe '#list' do
      it 'serializes amount_from/to, start/end_date and descriptions' do
        allow(client).to receive(:list_expected_payments).and_return([expected_payment])

        rows = collection.list(nil, Filter.new,
                               %w[id amount_from amount_to start_date end_date descriptions])

        expect(rows.first).to include(
          'amount_from' => 5000, 'amount_to' => 6000,
          'start_date' => '2026-05-11', 'end_date' => '2026-05-11',
          'descriptions' => ['test expected payment']
        )
      end

      it 'returns rows without resolving relations when projection has no relation prefix' do
        allow(client).to receive(:list_expected_payments).and_return([expected_payment])
        allow(client).to receive(:find_connected_account)
        allow(client).to receive(:find_internal_account)
        allow(client).to receive(:find_external_account)

        collection.list(nil, Filter.new, %w[id amount_from])

        expect(client).not_to have_received(:find_connected_account)
        expect(client).not_to have_received(:find_internal_account)
        expect(client).not_to have_received(:find_external_account)
      end

      it 'embeds connected_account when requested' do
        allow(client).to receive(:list_expected_payments).and_return([expected_payment])
        allow(client).to receive(:find_connected_account)
          .with('456d2975-d58b-4a90-89b8-efcc3239c866')
          .and_return(account.merge('id' => '456d2975-d58b-4a90-89b8-efcc3239c866'))

        rows = collection.list(nil, Filter.new, ['id', 'connected_account:name'])
        expect(rows.first['connected_account']).to include('name' => 'Acme')
      end

      it 'skips internal/external account fetches when their FK is the empty string' do
        allow(client).to receive(:list_expected_payments).and_return([expected_payment])
        allow(client).to receive(:find_internal_account)
        allow(client).to receive(:find_external_account)

        collection.list(nil, Filter.new, ['id', 'internal_account:id', 'external_account:id'])

        expect(client).not_to have_received(:find_internal_account)
        expect(client).not_to have_received(:find_external_account)
      end

      it 'short-circuits to find_expected_payment on id lookup' do
        allow(client).to receive(:find_expected_payment)
          .with('019e17e6-bac7-7607-9d91-12147d8db4c8').and_return(expected_payment)
        allow(client).to receive(:list_expected_payments)

        filter = Filter.new(condition_tree: Leaf.new('id', 'equal', '019e17e6-bac7-7607-9d91-12147d8db4c8'))
        collection.list(nil, filter, nil)

        expect(client).to have_received(:find_expected_payment)
        expect(client).not_to have_received(:list_expected_payments)
      end
    end

    describe '#create' do
      it 'strips system-managed fields before POSTing' do
        allow(client).to receive(:create_expected_payment) do |payload|
          expect(payload).to include('amount_from' => 5000, 'amount_to' => 6000, 'direction' => 'debit')
          expect(payload.keys).not_to include('id', 'object', 'reconciliation_status', 'reconciled_amount',
                                              'created_at', 'updated_at', 'canceled_at')
          { 'id' => 'ep1', 'amount_from' => 5000 }
        end

        collection.create(nil,
                          'id' => 'ignored', 'object' => 'expected_payment',
                          'reconciliation_status' => 'unreconciled', 'reconciled_amount' => 0,
                          'created_at' => 't', 'updated_at' => 't', 'canceled_at' => nil,
                          'amount_from' => 5000, 'amount_to' => 6000, 'direction' => 'debit')

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
                          'amount_to' => 7000)

        expect(client).to have_received(:update_expected_payment).with('a', hash_including('amount_to' => 7000))
        expect(client).to have_received(:update_expected_payment).with('b', hash_including('amount_to' => 7000))
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
