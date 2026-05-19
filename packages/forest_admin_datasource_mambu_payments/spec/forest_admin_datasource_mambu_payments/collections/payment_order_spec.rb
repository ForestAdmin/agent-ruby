module ForestAdminDatasourceMambuPayments
  include ForestAdminDatasourceToolkit::Components::Query

  Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  RSpec.describe Collections::PaymentOrder do
    let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client)
    end
    let(:ca_collection) { Collections::ConnectedAccount.new(datasource) }
    let(:collection) { described_class.new(datasource) }

    let(:account) { { 'id' => 'acc1', 'name' => 'Acme' } }
    let(:payment_order) do
      {
        'id' => 'po1', 'object' => 'payment_order',
        'connected_account_id' => 'acc1',
        'type' => 'sepa_instant', 'direction' => 'credit',
        'status' => 'sent', 'amount' => 1000, 'currency' => 'EUR',
        'reference' => 'REF', 'purpose' => '', 'end_to_end_id' => 'e2e',
        'originating_account' => { 'account_number' => 'BE..' },
        'receiving_account' => { 'account_number' => 'NL..' },
        'created_at' => '2026-05-04T08:50:28Z'
      }
    end

    before do
      allow(datasource).to receive(:get_collection).with('MambuConnectedAccount').and_return(ca_collection)
    end

    describe 'schema' do
      it 'declares the API-aligned columns' do
        keys = collection.schema[:fields].keys
        expect(keys).to include(
          'id', 'connected_account_id', 'type', 'direction', 'status', 'amount',
          'currency', 'reference', 'purpose', 'end_to_end_id', 'idempotency_key',
          'value_date', 'initiated_at', 'requested_execution_date',
          'reconciliation_status', 'reconciled_amount',
          'originating_account', 'receiving_account', 'metadata', 'custom_fields',
          'created_at'
        )
      end

      it 'declares a ManyToOne relation to connected_account via connected_account_id' do
        rel = collection.schema[:fields]['connected_account']
        expect(rel).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
        expect(rel.foreign_key).to eq('connected_account_id')
        expect(rel.foreign_key_target).to eq('id')
      end

      it 'keeps originating_account / receiving_account as Json (embedded snapshots)' do
        f = collection.schema[:fields]
        expect(f['originating_account'].column_type).to eq('Json')
        expect(f['receiving_account'].column_type).to eq('Json')
      end
    end

    describe '#list' do
      it 'returns rows without resolving the relation when projection has no relation prefix' do
        allow(client).to receive(:list_payment_orders).and_return([payment_order])
        allow(client).to receive(:find_connected_account)

        rows = collection.list(nil, Filter.new, ['id', 'connected_account_id'])

        expect(rows).to eq([{ 'id' => 'po1', 'connected_account_id' => 'acc1' }])
        expect(client).not_to have_received(:find_connected_account)
      end

      it 'embeds connected_account when the projection asks for it' do
        allow(client).to receive(:list_payment_orders).and_return([payment_order])
        allow(client).to receive(:find_connected_account).with('acc1').and_return(account)

        rows = collection.list(nil, Filter.new, ['id', 'connected_account:name'])

        expect(rows.first['connected_account']).to include('id' => 'acc1', 'name' => 'Acme')
      end

      it 'fetches a unique FK only once across multiple rows' do
        allow(client).to receive(:list_payment_orders).and_return([payment_order, payment_order, payment_order])
        allow(client).to receive(:find_connected_account).with('acc1').and_return(account)

        collection.list(nil, Filter.new, ['id', 'connected_account:name'])

        expect(client).to have_received(:find_connected_account).with('acc1').once
      end

      it 'short-circuits to find_payment_order on id lookup' do
        allow(client).to receive(:find_payment_order).with('po1').and_return(payment_order)
        allow(client).to receive(:list_payment_orders)

        filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 'po1'))
        collection.list(nil, filter, nil)

        expect(client).to have_received(:find_payment_order).with('po1')
        expect(client).not_to have_received(:list_payment_orders)
      end

      it 'forwards a translated connected_account_id filter to the API' do
        allow(client).to receive(:list_payment_orders).and_return([])

        filter = Filter.new(condition_tree: Leaf.new('connected_account_id', 'equal', 'acc1'))
        collection.list(nil, filter, ['id'])

        expect(client).to have_received(:list_payment_orders)
          .with(hash_including('connected_account_id' => 'acc1', page: 1))
      end

      it 'raises a clear error on an undeclared filter rather than silently dropping it' do
        allow(client).to receive(:list_payment_orders)

        filter = Filter.new(condition_tree: Leaf.new('status', 'equal', 'pending_approval'))

        expect { collection.list(nil, filter, ['id']) }
          .to raise_error(UnsupportedOperatorError, /'status'/)
        expect(client).not_to have_received(:list_payment_orders)
      end
    end

    describe '#create' do
      it 'strips system-managed fields before POSTing' do
        allow(client).to receive(:create_payment_order) do |payload|
          expect(payload).to include('amount' => 1000)
          expect(payload.keys).not_to include('id', 'status', 'created_at', 'value_date', 'initiated_at',
                                              'reconciliation_status', 'reconciled_amount')
          { 'id' => 'po1', 'connected_account_id' => 'acc1', 'amount' => 1000 }
        end

        collection.create(nil,
                          'id' => 'ignored', 'status' => 'sent',
                          'created_at' => 't', 'value_date' => 't',
                          'initiated_at' => 't', 'reconciliation_status' => 'r',
                          'reconciled_amount' => 0, 'amount' => 1000)

        expect(client).to have_received(:create_payment_order)
      end
    end

    describe '#update' do
      it 'PATCHes each id resolved by the filter' do
        allow(client).to receive(:find_payment_order).with('a').and_return('id' => 'a')
        allow(client).to receive(:find_payment_order).with('b').and_return('id' => 'b')
        allow(client).to receive(:update_payment_order)

        collection.update(nil,
                          Filter.new(condition_tree: Leaf.new('id', 'in', %w[a b])),
                          'amount' => 200)

        expect(client).to have_received(:update_payment_order).with('a', hash_including('amount' => 200))
        expect(client).to have_received(:update_payment_order).with('b', hash_including('amount' => 200))
      end
    end

    describe '#delete' do
      it 'DELETEs each id resolved by the filter' do
        allow(client).to receive(:find_payment_order).with('a').and_return('id' => 'a')
        allow(client).to receive(:delete_payment_order)

        collection.delete(nil, Filter.new(condition_tree: Leaf.new('id', 'equal', 'a')))

        expect(client).to have_received(:delete_payment_order).with('a')
      end
    end
  end
end
