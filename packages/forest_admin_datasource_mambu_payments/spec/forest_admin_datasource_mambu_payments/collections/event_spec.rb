module ForestAdminDatasourceMambuPayments
  include ForestAdminDatasourceToolkit::Components::Query

  Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  RSpec.describe Collections::Event do
    let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client)
    end
    let(:po_collection) { Collections::PaymentOrder.new(datasource) }
    let(:tx_collection) { Collections::Transaction.new(datasource) }
    let(:collection) { described_class.new(datasource) }

    let(:payment_order_event) do
      {
        'id' => 'ev1', 'object' => 'event',
        'topic' => 'payment_order', 'type' => 'executed',
        'related_object_id' => 'po1', 'related_object_type' => 'payment_order',
        'status' => 'delivered', 'status_details' => '',
        'webhook_id' => 'wh1',
        'data' => { 'id' => 'po1', 'connected_account_id' => 'acc1' },
        'created_at' => '2026-03-12T03:30:06Z'
      }
    end

    let(:transaction_event) do
      {
        'id' => 'ev2', 'object' => 'event',
        'topic' => 'transaction', 'type' => 'created',
        'related_object_id' => 'tx1', 'related_object_type' => 'transaction',
        'status' => 'created', 'status_details' => nil,
        'webhook_id' => nil,
        'data' => { 'id' => 'tx1' },
        'created_at' => '2026-03-12T03:31:00Z'
      }
    end

    before do
      allow(datasource).to receive(:get_collection).with('MambuPaymentOrder').and_return(po_collection)
      allow(datasource).to receive(:get_collection).with('MambuTransaction').and_return(tx_collection)
    end

    describe 'schema' do
      it 'declares the API-aligned columns' do
        keys = collection.schema[:fields].keys
        expect(keys).to include(
          'id', 'object', 'topic', 'type',
          'related_object_id', 'related_object_type',
          'status', 'status_details', 'webhook_id', 'data', 'created_at'
        )
      end

      it 'exposes status as an Enum with the Numeral lifecycle values' do
        f = collection.schema[:fields]
        expect(f['status'].column_type).to eq('Enum')
        expect(f['status'].enum_values)
          .to contain_exactly('created', 'delivered', 'pending_retry', 'failed', 'archived')
      end

      it 'declares a PolymorphicManyToOne relation to every Mambu collection' do
        rels = collection.schema[:fields].select do |_, v|
          v.is_a?(ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicManyToOneSchema)
        end
        expect(rels.keys).to contain_exactly('related_object')
        rel = rels['related_object']
        expect(rel.foreign_key).to eq('related_object_id')
        expect(rel.foreign_key_type_field).to eq('related_object_type')
        expect(rel.foreign_collections).to contain_exactly(
          'MambuPaymentOrder', 'MambuTransaction', 'MambuIncomingPayment',
          'MambuExpectedPayment', 'MambuDirectDebitMandate', 'MambuBalance',
          'MambuConnectedAccount', 'MambuAccountHolder',
          'MambuInternalAccount', 'MambuExternalAccount'
        )
      end

      it 'marks every column as read-only (events are immutable)' do
        f = collection.schema[:fields]
        %w[topic type status webhook_id data related_object_id related_object_type].each do |k|
          expect(f[k].is_read_only).to be(true), "#{k} should be read-only"
        end
      end

      it 'does not implement create / update / delete' do
        expect(collection.public_methods(false)).not_to include(:create, :update, :delete)
      end
    end

    describe '#serialize' do
      it 'translates related_object_type from the Numeral string to the Forest collection name' do
        row = collection.serialize(payment_order_event)
        expect(row['related_object_type']).to eq('MambuPaymentOrder')
        expect(row['topic']).to eq('payment_order')
      end

      it 'keeps the raw type string when it is not in the known mapping' do
        row = collection.serialize(payment_order_event.merge('related_object_type' => 'webhook'))
        expect(row['related_object_type']).to eq('webhook')
      end
    end

    describe '#list with server-side filter' do
      it 'forwards related_object_id equality to the Numeral list endpoint' do
        allow(client).to receive(:list_events).and_return([])

        filter = Filter.new(condition_tree: Leaf.new('related_object_id', 'equal', 'po1'))
        collection.list(nil, filter, %w[id])

        expect(client).to have_received(:list_events)
          .with(hash_including('related_object_id' => 'po1'))
      end

      it 'forwards related_object_id IN to the Numeral list endpoint' do
        allow(client).to receive(:list_events).and_return([])

        filter = Filter.new(condition_tree: Leaf.new('related_object_id', 'in', %w[po1 po2]))
        collection.list(nil, filter, %w[id])

        expect(client).to have_received(:list_events)
          .with(hash_including('related_object_id' => %w[po1 po2]))
      end
    end

    describe '#list' do
      it 'returns rows without resolving related_object when projection has no relation prefix' do
        allow(client).to receive(:list_events).and_return([payment_order_event])
        allow(client).to receive(:find_payment_order)

        rows = collection.list(nil, Filter.new, ['id', 'topic'])

        expect(rows).to eq([{ 'id' => 'ev1', 'topic' => 'payment_order' }])
        expect(client).not_to have_received(:find_payment_order)
      end

      it 'embeds the related payment_order when requested by the projection' do
        allow(client).to receive(:list_events).and_return([payment_order_event])
        allow(client).to receive(:find_payment_order).with('po1')
                                                     .and_return('id' => 'po1', 'amount' => 75_000)

        rows = collection.list(nil, Filter.new, ['id', 'related_object:id'])

        expect(rows.first['related_object']).to include('id' => 'po1', 'amount' => 75_000)
      end

      it 'batches per related collection and avoids duplicate find_* calls' do
        allow(client).to receive(:list_events)
          .and_return([payment_order_event, payment_order_event, transaction_event])
        allow(client).to receive(:find_payment_order).with('po1').and_return('id' => 'po1')
        allow(client).to receive(:find_transaction).with('tx1').and_return('id' => 'tx1')

        collection.list(nil, Filter.new, ['id', 'related_object:id'])

        expect(client).to have_received(:find_payment_order).with('po1').once
        expect(client).to have_received(:find_transaction).with('tx1').once
      end

      it 'leaves related_object unset when the related_object_type is unknown' do
        unknown = payment_order_event.merge('related_object_type' => 'webhook')
        allow(client).to receive(:list_events).and_return([unknown])

        rows = collection.list(nil, Filter.new, ['id', 'related_object:id'])

        expect(rows.first).not_to have_key('related_object')
      end

      it 'short-circuits to find_event on id lookup' do
        allow(client).to receive(:find_event).with('ev1').and_return(payment_order_event)
        allow(client).to receive(:list_events)

        filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 'ev1'))
        collection.list(nil, filter, nil)

        expect(client).to have_received(:find_event).with('ev1')
        expect(client).not_to have_received(:list_events)
      end

      it 'projects to the requested column subset' do
        allow(client).to receive(:list_events).and_return([payment_order_event])
        rows = collection.list(nil, Filter.new, %w[id status topic])
        expect(rows.first).to eq('id' => 'ev1', 'status' => 'delivered', 'topic' => 'payment_order')
      end
    end

    describe '#aggregate Count' do
      it 'counts via the server-side total' do
        allow(client).to receive(:count_events).and_return(2)
        result = collection.aggregate(nil, Filter.new, Aggregation.new(operation: 'Count'))
        expect(result.first['value']).to eq(2)
      end
    end
  end
end
