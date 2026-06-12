module ForestAdminDatasourceMambuPayments
  include ForestAdminDatasourceToolkit::Components::Query

  Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  RSpec.describe Collections::PaymentCapture do
    let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client)
    end
    let(:ca_collection) { Collections::ConnectedAccount.new(datasource) }
    let(:collection) { described_class.new(datasource) }

    let(:account) { { 'id' => 'acc1', 'name' => 'Acme' } }
    let(:payment_capture) do
      {
        'id' => 'pc1', 'object' => 'payment_capture',
        'idempotency_key' => 'idem-1',
        'connected_account_id' => 'acc1',
        'type' => 'charge', 'source' => 'reporting_file',
        'amount' => 2000, 'original_payment_amount' => nil,
        'currency' => 'EUR',
        'date' => '2026-05-20', 'value_date' => '2026-05-21',
        'remittance_date' => '2026-05-22', 'remittance_reference' => 'REM-1',
        'transaction_reference' => 'TXN-1', 'authorization_id' => 'AUTH-1',
        'payment_reference' => 'PR-1', 'network' => 'visa',
        'merchant_id' => 'M-1',
        'fee_amount' => 10, 'fee_amount_currency' => 'EUR',
        'net_amount' => 1990, 'net_amount_currency' => 'EUR',
        'reconciliation_status' => 'unreconciled', 'reconciled_amount' => 0,
        'cbs_data' => { 'sys' => 'core' }, 'lending' => { 'loan_ids' => [] },
        'metadata' => { 'src' => 'sandbox' },
        'canceled_at' => nil, 'updated_at' => '2026-05-21T08:00:00Z',
        'created_at' => '2026-05-20T10:00:00Z'
      }
    end

    before do
      allow(datasource).to receive(:get_collection).with('MambuConnectedAccount').and_return(ca_collection)
    end

    describe 'schema' do
      it 'declares the API-aligned columns' do
        keys = collection.schema[:fields].keys
        expect(keys).to include(
          'id', 'object', 'idempotency_key', 'connected_account_id',
          'type', 'source', 'amount', 'original_payment_amount', 'currency',
          'date', 'value_date', 'remittance_date', 'remittance_reference',
          'transaction_reference', 'authorization_id', 'payment_reference',
          'network', 'merchant_id',
          'fee_amount', 'fee_amount_currency', 'net_amount', 'net_amount_currency',
          'reconciliation_status', 'reconciled_amount',
          'cbs_data', 'lending', 'metadata',
          'canceled_at', 'updated_at', 'created_at'
        )
      end

      it 'declares a ManyToOne relation to connected_account via connected_account_id' do
        rel = collection.schema[:fields]['connected_account']
        expect(rel).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
        expect(rel.foreign_key).to eq('connected_account_id')
        expect(rel.foreign_key_target).to eq('id')
      end

      it 'exposes only connected_account as a typed relation' do
        rels = collection.schema[:fields].select do |_, v|
          v.is_a?(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
        end
        expect(rels.keys).to contain_exactly('connected_account')
      end

      it 'marks every column as read-only (payment captures are PSP-emitted)' do
        f = collection.schema[:fields]
        %w[id type source amount currency date value_date reconciliation_status
           reconciled_amount metadata canceled_at updated_at created_at].each do |k|
          expect(f[k].is_read_only).to be(true), "#{k} should be read-only"
        end
      end

      it 'exposes type, source and reconciliation_status as Enum columns with Numeral values' do
        f = collection.schema[:fields]
        expect(f['type'].column_type).to eq('Enum')
        expect(f['type'].enum_values).to contain_exactly('charge', 'chargeback', 'refund')
        expect(f['source'].column_type).to eq('Enum')
        expect(f['source'].enum_values).to contain_exactly('api', 'reporting_file')
        expect(f['reconciliation_status'].column_type).to eq('Enum')
        expect(f['reconciliation_status'].enum_values)
          .to contain_exactly('unreconciled', 'reconciled', 'partially_reconciled')
      end

      it 'keeps cbs_data, lending and metadata as Json' do
        f = collection.schema[:fields]
        expect(f['cbs_data'].column_type).to eq('Json')
        expect(f['lending'].column_type).to eq('Json')
        expect(f['metadata'].column_type).to eq('Json')
      end

      it 'does not implement create / update / delete' do
        expect(collection.public_methods(false)).not_to include(:create, :update, :delete)
      end
    end

    describe '#serialize' do
      it 'maps the API record to a flat hash with the schema fields' do
        result = collection.serialize(payment_capture)
        expect(result).to include(
          'id' => 'pc1', 'type' => 'charge', 'source' => 'reporting_file',
          'amount' => 2000, 'currency' => 'EUR',
          'connected_account_id' => 'acc1', 'reconciliation_status' => 'unreconciled'
        )
      end

      it 'keeps cbs_data, lending and metadata as embedded Json snapshots' do
        result = collection.serialize(payment_capture)
        expect(result['cbs_data']).to eq('sys' => 'core')
        expect(result['lending']).to eq('loan_ids' => [])
        expect(result['metadata']).to eq('src' => 'sandbox')
      end
    end

    describe '#list' do
      it 'returns rows without resolving the relation when projection has no relation prefix' do
        allow(client).to receive(:list_payment_captures).and_return([payment_capture])
        allow(client).to receive(:find_connected_account)

        rows = collection.list(nil, Filter.new, %w[id type amount])

        expect(rows).to eq([{ 'id' => 'pc1', 'type' => 'charge', 'amount' => 2000 }])
        expect(client).not_to have_received(:find_connected_account)
      end

      it 'embeds connected_account when the projection asks for it' do
        allow(client).to receive(:list_payment_captures).and_return([payment_capture])
        allow(client).to receive(:find_connected_account).with('acc1').and_return(account)

        rows = collection.list(nil, Filter.new, ['id', 'connected_account:name'])

        expect(rows.first['connected_account']).to include('id' => 'acc1', 'name' => 'Acme')
      end

      it 'short-circuits to find_payment_capture on id lookup' do
        allow(client).to receive(:find_payment_capture).with('pc1').and_return(payment_capture)
        allow(client).to receive(:list_payment_captures)

        filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 'pc1'))
        collection.list(nil, filter, nil)

        expect(client).to have_received(:find_payment_capture).with('pc1')
        expect(client).not_to have_received(:list_payment_captures)
      end

      it 'drops 404 (nil) records from the result on id lookup' do
        allow(client).to receive(:find_payment_capture).and_return(nil)
        filter = Filter.new(condition_tree: Leaf.new('id', 'in', %w[missing]))
        expect(collection.list(nil, filter, nil)).to eq([])
      end

      it 'forwards translated connected_account_id, type, source and reconciliation_status filters' do
        allow(client).to receive(:list_payment_captures).and_return([])

        filter = Filter.new(condition_tree: Leaf.new('type', 'equal', 'refund'))
        collection.list(nil, filter, ['id'])
        expect(client).to have_received(:list_payment_captures).with(hash_including('type' => 'refund'))

        filter = Filter.new(condition_tree: Leaf.new('source', 'equal', 'reporting_file'))
        collection.list(nil, filter, ['id'])
        expect(client).to have_received(:list_payment_captures)
          .with(hash_including('source' => 'reporting_file'))

        filter = Filter.new(condition_tree: Leaf.new('reconciliation_status', 'equal', 'reconciled'))
        collection.list(nil, filter, ['id'])
        expect(client).to have_received(:list_payment_captures)
          .with(hash_including('reconciliation_status' => 'reconciled'))
      end

      it 'raises a clear error on an undeclared filter rather than silently dropping it' do
        allow(client).to receive(:list_payment_captures)

        filter = Filter.new(condition_tree: Leaf.new('merchant_id', 'equal', 'M-1'))

        expect { collection.list(nil, filter, ['id']) }
          .to raise_error(UnsupportedOperatorError, /'merchant_id'/)
        expect(client).not_to have_received(:list_payment_captures)
      end
    end
  end
end
