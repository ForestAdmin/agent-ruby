module ForestAdminDatasourceMambuPayments
  include ForestAdminDatasourceToolkit::Components::Query

  Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  RSpec.describe Collections::Claim do
    let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client)
    end
    let(:ca_collection) { Collections::ConnectedAccount.new(datasource) }
    let(:collection) { described_class.new(datasource) }

    let(:account) { { 'id' => 'acc1', 'name' => 'Acme' } }
    let(:claim) do
      {
        'id' => 'clm1', 'object' => 'claim',
        'type' => 'sepa_non_receipt',
        'status' => 'received', 'status_details' => nil, 'reason' => nil,
        'value_date' => '2026-05-20',
        'connected_account_id' => 'acc1',
        'related_payment_type' => 'payment_order',
        'related_payment_id' => 'po1',
        'related_payment' => { 'id' => 'po1', 'amount' => 5000 },
        'metadata' => {},
        'bank_data' => { 'message_id' => 'msg-1' },
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
          'id', 'object', 'type', 'status', 'status_details', 'reason',
          'value_date', 'connected_account_id',
          'related_payment_type', 'related_payment_id', 'related_payment',
          'metadata', 'bank_data', 'created_at'
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

      it 'marks every column as read-only (claims are bank-emitted)' do
        f = collection.schema[:fields]
        %w[id type status status_details reason value_date connected_account_id
           related_payment_type related_payment_id related_payment
           metadata bank_data created_at].each do |k|
          expect(f[k].is_read_only).to be(true), "#{k} should be read-only"
        end
      end

      it 'exposes type, status and related_payment_type as Enum columns with Numeral values' do
        f = collection.schema[:fields]
        expect(f['type'].column_type).to eq('Enum')
        expect(f['type'].enum_values).to include('sepa_non_receipt', 'sepa_value_date_correction')
        expect(f['status'].column_type).to eq('Enum')
        expect(f['status'].enum_values).to include('created', 'processing', 'sent', 'received',
                                                   'accepted', 'rejected')
        expect(f['related_payment_type'].column_type).to eq('Enum')
        expect(f['related_payment_type'].enum_values).to include('payment_order', 'incoming_payment')
      end

      it 'does not implement create / update / delete' do
        expect(collection.public_methods(false)).not_to include(:create, :update, :delete)
      end
    end

    describe '#serialize' do
      it 'maps the API record to a flat hash with the schema fields' do
        result = collection.serialize(claim)
        expect(result).to include(
          'id' => 'clm1', 'type' => 'sepa_non_receipt', 'status' => 'received',
          'connected_account_id' => 'acc1',
          'related_payment_type' => 'payment_order', 'related_payment_id' => 'po1'
        )
      end

      it 'keeps related_payment and bank_data as embedded Json snapshots' do
        result = collection.serialize(claim)
        expect(result['related_payment']).to eq('id' => 'po1', 'amount' => 5000)
        expect(result['bank_data']).to eq('message_id' => 'msg-1')
      end
    end

    describe '#list' do
      it 'returns rows without resolving the relation when projection has no relation prefix' do
        allow(client).to receive(:list_claims).and_return([claim])
        allow(client).to receive(:find_connected_account)

        rows = collection.list(nil, Filter.new, ['id', 'status'])

        expect(rows).to eq([{ 'id' => 'clm1', 'status' => 'received' }])
        expect(client).not_to have_received(:find_connected_account)
      end

      it 'embeds connected_account when the projection asks for it' do
        allow(client).to receive(:list_claims).and_return([claim])
        allow(client).to receive(:find_connected_account).with('acc1').and_return(account)

        rows = collection.list(nil, Filter.new, ['id', 'connected_account:name'])

        expect(rows.first['connected_account']).to include('id' => 'acc1', 'name' => 'Acme')
      end

      it 'short-circuits to find_claim on id lookup' do
        allow(client).to receive(:find_claim).with('clm1').and_return(claim)
        allow(client).to receive(:list_claims)

        filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 'clm1'))
        collection.list(nil, filter, nil)

        expect(client).to have_received(:find_claim).with('clm1')
        expect(client).not_to have_received(:list_claims)
      end

      it 'drops 404 (nil) records from the result on id lookup' do
        allow(client).to receive(:find_claim).and_return(nil)
        filter = Filter.new(condition_tree: Leaf.new('id', 'in', %w[missing]))
        expect(collection.list(nil, filter, nil)).to eq([])
      end

      it 'forwards a translated related_payment_id filter to the API' do
        allow(client).to receive(:list_claims).and_return([])

        filter = Filter.new(condition_tree: Leaf.new('related_payment_id', 'equal', 'po1'))
        collection.list(nil, filter, ['id'])

        expect(client).to have_received(:list_claims)
          .with(hash_including('related_payment_id' => 'po1', page: 1))
      end

      it 'forwards status and type filters to the API' do
        allow(client).to receive(:list_claims).and_return([])

        filter = Filter.new(condition_tree: Leaf.new('status', 'equal', 'rejected'))
        collection.list(nil, filter, ['id'])

        expect(client).to have_received(:list_claims).with(hash_including('status' => 'rejected'))
      end

      it 'raises a clear error on an undeclared filter rather than silently dropping it' do
        allow(client).to receive(:list_claims)

        filter = Filter.new(condition_tree: Leaf.new('reason', 'equal', 'NOOR'))

        expect { collection.list(nil, filter, ['id']) }
          .to raise_error(UnsupportedOperatorError, /'reason'/)
        expect(client).not_to have_received(:list_claims)
      end
    end

    describe '#aggregate Count' do
      it 'counts via the server-side total' do
        allow(client).to receive(:count_claims).and_return(2)
        result = collection.aggregate(nil, Filter.new, Aggregation.new(operation: 'Count'))
        expect(result.first['value']).to eq(2)
      end
    end
  end
end
