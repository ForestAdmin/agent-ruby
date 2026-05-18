module ForestAdminDatasourceMambuPayments
  include ForestAdminDatasourceToolkit::Components::Query

  Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  RSpec.describe Collections::File do
    let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client)
    end
    let(:ca_collection) { Collections::ConnectedAccount.new(datasource) }
    let(:collection) { described_class.new(datasource) }

    let(:account) { { 'id' => 'acc1', 'name' => 'Acme' } }
    let(:file_record) do
      {
        'id' => 'f1', 'object' => 'file',
        'connected_account_id' => 'acc1',
        'connected_account_ids' => %w[acc1 acc2],
        'direction' => 'outgoing', 'category' => 'payment_file',
        'format' => 'pain.001', 'filename' => 'SFPP30X40.f1.1659349967',
        'size' => 2234, 'summary' => {},
        'status' => 'sent', 'status_details' => 'generated on 2024-08-01',
        'bank_data' => { 'message_ids' => ['211012231391882'] },
        'created_at' => '2024-08-01T06:00:05Z'
      }
    end

    before do
      allow(datasource).to receive(:get_collection).with('MambuConnectedAccount').and_return(ca_collection)
    end

    describe 'schema' do
      it 'declares the API-aligned columns' do
        keys = collection.schema[:fields].keys
        expect(keys).to include(
          'id', 'object', 'connected_account_id', 'connected_account_ids',
          'direction', 'category', 'format', 'filename', 'size', 'summary',
          'status', 'status_details', 'bank_data', 'created_at'
        )
      end

      it 'exposes direction and status as Enum columns with the Numeral values' do
        f = collection.schema[:fields]
        expect(f['direction'].column_type).to eq('Enum')
        expect(f['direction'].enum_values).to contain_exactly('incoming', 'outgoing')
        expect(f['status'].column_type).to eq('Enum')
        expect(f['status'].enum_values).to contain_exactly(
          'created', 'approved', 'canceled', 'sent', 'rejected', 'processed', 'received'
        )
      end

      it 'declares a ManyToOne to connected_account' do
        rels = collection.schema[:fields].select do |_, v|
          v.is_a?(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
        end
        expect(rels.keys).to contain_exactly('connected_account')
      end

      it 'keeps connected_account_ids as a Json array (files can span several accounts)' do
        f = collection.schema[:fields]
        expect(f['connected_account_ids'].column_type).to eq('Json')
      end

      it 'marks every column as read-only (files are bank-emitted)' do
        f = collection.schema[:fields]
        %w[direction category format filename status size summary bank_data].each do |k|
          expect(f[k].is_read_only).to be(true), "#{k} should be read-only"
        end
      end

      it 'does not implement create / update / delete' do
        expect(collection.public_methods(false)).not_to include(:create, :update, :delete)
      end
    end

    describe '#list' do
      it 'returns rows without resolving connected_account when projection has no relation prefix' do
        allow(client).to receive(:list_files).and_return([file_record])
        allow(client).to receive(:find_connected_account)

        rows = collection.list(nil, Filter.new, %w[id filename])

        expect(rows).to eq([{ 'id' => 'f1', 'filename' => 'SFPP30X40.f1.1659349967' }])
        expect(client).not_to have_received(:find_connected_account)
      end

      it 'embeds connected_account when requested by the projection' do
        allow(client).to receive(:list_files).and_return([file_record])
        allow(client).to receive(:find_connected_account).with('acc1').and_return(account)

        rows = collection.list(nil, Filter.new, ['id', 'connected_account:name'])
        expect(rows.first['connected_account']).to include('name' => 'Acme')
      end

      it 'short-circuits to find_file on id lookup' do
        allow(client).to receive(:find_file).with('f1').and_return(file_record)
        allow(client).to receive(:list_files)

        filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 'f1'))
        collection.list(nil, filter, nil)

        expect(client).to have_received(:find_file).with('f1')
        expect(client).not_to have_received(:list_files)
      end

      it 'projects to the requested column subset' do
        allow(client).to receive(:list_files).and_return([file_record])
        rows = collection.list(nil, Filter.new, %w[id status direction format])
        expect(rows.first).to eq(
          'id' => 'f1', 'status' => 'sent', 'direction' => 'outgoing', 'format' => 'pain.001'
        )
      end
    end

    describe '#aggregate Count' do
      it 'counts via list with a minimal projection' do
        allow(client).to receive(:list_files).and_return([file_record, file_record])
        result = collection.aggregate(nil, Filter.new, Aggregation.new(operation: 'Count'))
        expect(result.first['value']).to eq(2)
      end
    end
  end
end
