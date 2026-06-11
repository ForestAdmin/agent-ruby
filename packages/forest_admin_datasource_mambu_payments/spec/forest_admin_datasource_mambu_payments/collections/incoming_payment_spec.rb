module ForestAdminDatasourceMambuPayments
  include ForestAdminDatasourceToolkit::Components::Query

  Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  RSpec.describe Collections::IncomingPayment do
    let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client)
    end
    let(:ca_collection) { Collections::ConnectedAccount.new(datasource) }
    let(:ia_collection) { Collections::InternalAccount.new(datasource) }
    let(:ea_collection) { Collections::ExternalAccount.new(datasource) }
    let(:collection) { described_class.new(datasource) }

    let(:account) { { 'id' => 'acc1', 'name' => 'Acme' } }
    let(:incoming_payment) do
      {
        'id' => 'ip1', 'object' => 'incoming_payment',
        'connected_account_id' => 'acc1',
        'type' => 'sepa_credit_transfer', 'status' => 'received',
        'amount' => 12_500, 'currency' => 'EUR',
        'end_to_end_id' => 'e2e', 'uetr' => 'u-1',
        'reference' => 'REF', 'structured_reference' => nil,
        'value_date' => '2026-05-11', 'booking_date' => '2026-05-11',
        'originating_account' => { 'account_number' => 'DE..' },
        'receiving_account' => { 'account_number' => 'BE..' },
        'internal_account_id' => 'ia1', 'external_account_id' => 'ea1',
        'reconciliation_status' => 'unreconciled', 'reconciled_amount' => 0,
        'return_information' => nil, 'custom_fields' => {}, 'metadata' => {},
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
          'id', 'connected_account_id', 'type', 'status', 'amount', 'currency',
          'end_to_end_id', 'uetr', 'reference', 'structured_reference',
          'value_date', 'booking_date',
          'originating_account', 'receiving_account',
          'internal_account_id', 'external_account_id',
          'reconciliation_status', 'reconciled_amount', 'return_information',
          'custom_fields', 'metadata', 'created_at'
        )
      end

      it 'declares ManyToOne to connected_account, internal_account and external_account' do
        rels = collection.schema[:fields].select do |_, v|
          v.is_a?(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
        end
        expect(rels.keys).to contain_exactly('connected_account', 'internal_account', 'external_account')
      end

      it 'marks every column as read-only (incoming payments are immutable)' do
        f = collection.schema[:fields]
        %w[type status amount currency reference value_date booking_date custom_fields metadata].each do |k|
          expect(f[k].is_read_only).to be(true), "#{k} should be read-only"
        end
      end

      it 'does not implement create / update / delete' do
        expect(collection.public_methods(false)).not_to include(:create, :update, :delete)
      end

      it 'keeps originating_account / receiving_account as Json (embedded snapshots)' do
        f = collection.schema[:fields]
        expect(f['originating_account'].column_type).to eq('Json')
        expect(f['receiving_account'].column_type).to eq('Json')
      end
    end

    describe '#list' do
      it 'returns rows without resolving relations when projection has no relation prefix' do
        allow(client).to receive(:list_incoming_payments).and_return([incoming_payment])
        allow(client).to receive(:find_connected_account)
        allow(client).to receive(:find_internal_account)
        allow(client).to receive(:find_external_account)

        rows = collection.list(nil, Filter.new, ['id', 'amount'])

        expect(rows).to eq([{ 'id' => 'ip1', 'amount' => 12_500 }])
        expect(client).not_to have_received(:find_connected_account)
        expect(client).not_to have_received(:find_internal_account)
        expect(client).not_to have_received(:find_external_account)
      end

      it 'embeds connected_account when requested by the projection' do
        allow(client).to receive(:list_incoming_payments).and_return([incoming_payment])
        allow(client).to receive(:find_connected_account).with('acc1').and_return(account)

        rows = collection.list(nil, Filter.new, ['id', 'connected_account:name'])
        expect(rows.first['connected_account']).to include('name' => 'Acme')
      end

      it 'embeds internal_account and external_account when requested' do
        allow(client).to receive(:list_incoming_payments).and_return([incoming_payment])
        allow(client).to receive(:find_internal_account).with('ia1').and_return('id' => 'ia1')
        allow(client).to receive(:find_external_account).with('ea1').and_return('id' => 'ea1')

        rows = collection.list(nil, Filter.new, ['id', 'internal_account:id', 'external_account:id'])

        expect(rows.first['internal_account']).to include('id' => 'ia1')
        expect(rows.first['external_account']).to include('id' => 'ea1')
      end

      it 'short-circuits to find_incoming_payment on id lookup' do
        allow(client).to receive(:find_incoming_payment).with('ip1').and_return(incoming_payment)
        allow(client).to receive(:list_incoming_payments)

        filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 'ip1'))
        collection.list(nil, filter, nil)

        expect(client).to have_received(:find_incoming_payment).with('ip1')
        expect(client).not_to have_received(:list_incoming_payments)
      end

      it 'projects to the requested column subset' do
        allow(client).to receive(:list_incoming_payments).and_return([incoming_payment])
        rows = collection.list(nil, Filter.new, %w[id status amount])
        expect(rows.first).to eq('id' => 'ip1', 'status' => 'received', 'amount' => 12_500)
      end
    end

    describe '#aggregate Count' do
      it 'counts via the server-side total' do
        allow(client).to receive(:count_incoming_payments).and_return(2)
        result = collection.aggregate(nil, Filter.new, Aggregation.new(operation: 'Count'))
        expect(result.first['value']).to eq(2)
      end
    end
  end
end
