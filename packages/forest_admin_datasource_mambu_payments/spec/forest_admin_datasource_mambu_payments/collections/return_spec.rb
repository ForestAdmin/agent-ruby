module ForestAdminDatasourceMambuPayments
  include ForestAdminDatasourceToolkit::Components::Query

  Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  RSpec.describe Collections::Return do
    let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client)
    end
    let(:ca_collection) { Collections::ConnectedAccount.new(datasource) }
    let(:collection) { described_class.new(datasource) }

    let(:account) { { 'id' => 'acc1', 'name' => 'Acme' } }
    let(:return_record) do
      {
        'id' => 'ret1', 'object' => 'return',
        'connected_account_id' => 'acc1',
        'related_payment_id' => 'ip1', 'related_payment_type' => 'incoming_payment',
        'related_payment_suspended' => false,
        'return_type' => 'return', 'type' => 'sepa', 'direction' => 'debit',
        'status' => 'pending', 'status_details' => nil,
        'return_reason' => 'AC06',
        'amount' => 3000, 'currency' => 'EUR',
        'reconciliation_status' => 'unreconciled', 'reconciled_amount' => 0,
        'value_date' => '2026-05-20', 'booking_date' => '2026-05-20',
        'originating_account' => { 'account_number' => 'FR..' },
        'receiving_account' => { 'account_number' => 'DE..' },
        'aggregation_reference' => nil, 'file_id' => nil, 'metadata' => {},
        'created_at' => '2026-05-20T08:00:00Z'
      }
    end

    before do
      allow(datasource).to receive(:get_collection).with('MambuConnectedAccount').and_return(ca_collection)
    end

    describe 'schema' do
      it 'declares the API-aligned columns' do
        keys = collection.schema[:fields].keys
        expect(keys).to include(
          'id', 'connected_account_id', 'related_payment_id', 'related_payment_type',
          'related_payment_suspended', 'return_type', 'type', 'direction',
          'status', 'status_details', 'return_reason',
          'amount', 'currency', 'reconciliation_status', 'reconciled_amount',
          'value_date', 'booking_date', 'originating_account', 'receiving_account',
          'aggregation_reference', 'file_id', 'metadata', 'created_at'
        )
      end

      it 'declares a ManyToOne relation to connected_account via connected_account_id' do
        rel = collection.schema[:fields]['connected_account']
        expect(rel).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
        expect(rel.foreign_key).to eq('connected_account_id')
        expect(rel.foreign_key_target).to eq('id')
      end

      it 'does not expose a typed relation for related_payment_id (polymorphic in Numeral)' do
        rels = collection.schema[:fields].select do |_, v|
          v.is_a?(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
        end
        expect(rels.keys).to contain_exactly('connected_account')
      end

      it 'marks system-managed columns as read-only' do
        f = collection.schema[:fields]
        %w[id connected_account_id related_payment_type return_type type direction
           amount currency reconciliation_status reconciled_amount value_date booking_date
           originating_account receiving_account aggregation_reference file_id created_at].each do |k|
          expect(f[k].is_read_only).to be(true), "#{k} should be read-only"
        end
      end

      it 'keeps return_reason, status, status_details and metadata writable' do
        f = collection.schema[:fields]
        %w[return_reason status status_details metadata related_payment_id related_payment_suspended].each do |k|
          expect(f[k].is_read_only).to be(false), "#{k} should be writable"
        end
      end

      it 'does not implement delete (Numeral has no DELETE on /returns)' do
        expect(collection.public_methods(false)).not_to include(:delete)
      end
    end

    describe '#serialize' do
      it 'maps the API record to a flat hash with the schema fields' do
        result = collection.serialize(return_record)
        expect(result).to include(
          'id' => 'ret1', 'connected_account_id' => 'acc1',
          'related_payment_id' => 'ip1', 'related_payment_type' => 'incoming_payment',
          'return_reason' => 'AC06', 'status' => 'pending',
          'amount' => 3000, 'currency' => 'EUR'
        )
      end
    end

    describe '#list' do
      it 'returns rows without resolving the relation when projection has no relation prefix' do
        allow(client).to receive(:list_returns).and_return([return_record])
        allow(client).to receive(:find_connected_account)

        rows = collection.list(nil, Filter.new, ['id', 'connected_account_id'])

        expect(rows).to eq([{ 'id' => 'ret1', 'connected_account_id' => 'acc1' }])
        expect(client).not_to have_received(:find_connected_account)
      end

      it 'embeds connected_account when the projection asks for it' do
        allow(client).to receive(:list_returns).and_return([return_record])
        allow(client).to receive(:find_connected_account).with('acc1').and_return(account)

        rows = collection.list(nil, Filter.new, ['id', 'connected_account:name'])

        expect(rows.first['connected_account']).to include('id' => 'acc1', 'name' => 'Acme')
      end

      it 'short-circuits to find_return on id lookup' do
        allow(client).to receive(:find_return).with('ret1').and_return(return_record)
        allow(client).to receive(:list_returns)

        filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 'ret1'))
        collection.list(nil, filter, nil)

        expect(client).to have_received(:find_return).with('ret1')
        expect(client).not_to have_received(:list_returns)
      end

      it 'drops 404 (nil) records from the result on id lookup' do
        allow(client).to receive(:find_return).and_return(nil)
        filter = Filter.new(condition_tree: Leaf.new('id', 'in', %w[missing]))
        expect(collection.list(nil, filter, nil)).to eq([])
      end

      it 'forwards a translated related_payment_id filter to the API' do
        allow(client).to receive(:list_returns).and_return([])

        filter = Filter.new(condition_tree: Leaf.new('related_payment_id', 'equal', 'ip1'))
        collection.list(nil, filter, ['id'])

        expect(client).to have_received(:list_returns)
          .with(hash_including('related_payment_id' => 'ip1'))
      end

      it 'forwards status and connected_account_id filters to the API' do
        allow(client).to receive(:list_returns).and_return([])

        filter = Filter.new(condition_tree: Leaf.new('status', 'equal', 'executed'))
        collection.list(nil, filter, ['id'])

        expect(client).to have_received(:list_returns).with(hash_including('status' => 'executed'))
      end

      it 'raises a clear error on an undeclared filter rather than silently dropping it' do
        allow(client).to receive(:list_returns)

        filter = Filter.new(condition_tree: Leaf.new('return_reason', 'equal', 'AC06'))

        expect { collection.list(nil, filter, ['id']) }
          .to raise_error(UnsupportedOperatorError, /'return_reason'/)
        expect(client).not_to have_received(:list_returns)
      end
    end

    describe '#aggregate Count' do
      it 'counts via the server-side total' do
        allow(client).to receive(:count_returns).and_return(2)
        result = collection.aggregate(nil, Filter.new, Aggregation.new(operation: 'Count'))
        expect(result.first['value']).to eq(2)
      end
    end

    describe '#create' do
      it 'POSTs the payload stripping system-managed fields' do
        allow(client).to receive(:create_return) do |payload|
          expect(payload).to include('related_payment_id' => 'ip1', 'return_reason' => 'AC06')
          expect(payload.keys).not_to include(
            'id', 'object', 'connected_account_id', 'related_payment_type',
            'return_type', 'type', 'direction', 'amount', 'currency',
            'reconciliation_status', 'reconciled_amount',
            'value_date', 'booking_date',
            'originating_account', 'receiving_account',
            'aggregation_reference', 'file_id', 'created_at'
          )
          { 'id' => 'ret1', 'related_payment_id' => 'ip1', 'return_reason' => 'AC06' }
        end

        result = collection.create(nil,
                                   'id' => 'ignored', 'object' => 'return',
                                   'connected_account_id' => 'acc1',
                                   'related_payment_id' => 'ip1',
                                   'related_payment_type' => 'incoming_payment',
                                   'return_type' => 'return', 'type' => 'sepa',
                                   'direction' => 'debit',
                                   'amount' => 3000, 'currency' => 'EUR',
                                   'reconciliation_status' => 'unreconciled',
                                   'reconciled_amount' => 0,
                                   'value_date' => '2026-05-20',
                                   'booking_date' => '2026-05-20',
                                   'originating_account' => { 'account_number' => 'FR..' },
                                   'receiving_account' => { 'account_number' => 'DE..' },
                                   'aggregation_reference' => 'agg', 'file_id' => 'f1',
                                   'created_at' => 't',
                                   'return_reason' => 'AC06',
                                   'related_payment_suspended' => false,
                                   'metadata' => { 'test' => 'true' })
        expect(result['id']).to eq('ret1')
      end
    end

    describe '#update' do
      it 'PATCHes each id resolved by the filter with the writable subset only' do
        allow(client).to receive(:find_return).with('a').and_return('id' => 'a')
        allow(client).to receive(:find_return).with('b').and_return('id' => 'b')
        allow(client).to receive(:update_return)

        collection.update(nil,
                          Filter.new(condition_tree: Leaf.new('id', 'in', %w[a b])),
                          'status' => 'rejected',
                          'status_details' => 'duplicate',
                          'created_at' => 'ignored',
                          'amount' => 9999)

        %w[a b].each do |id|
          expect(client).to have_received(:update_return)
            .with(id, hash_including('status' => 'rejected', 'status_details' => 'duplicate'))
          expect(client).to have_received(:update_return)
            .with(id, hash_excluding('created_at', 'amount'))
        end
      end
    end
  end
end
