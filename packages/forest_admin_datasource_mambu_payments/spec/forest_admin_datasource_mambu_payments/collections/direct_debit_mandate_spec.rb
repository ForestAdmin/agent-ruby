module ForestAdminDatasourceMambuPayments
  include ForestAdminDatasourceToolkit::Components::Query

  Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  RSpec.describe Collections::DirectDebitMandate do
    let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client)
    end
    let(:ca_collection) { Collections::ConnectedAccount.new(datasource) }
    let(:ea_collection) { Collections::ExternalAccount.new(datasource) }
    let(:collection) { described_class.new(datasource) }

    let(:account) { { 'id' => 'acc1', 'name' => 'Acme' } }
    let(:mandate) do
      {
        'id' => 'dm1', 'object' => 'direct_debit_mandate',
        'connected_account_id' => 'acc1',
        'external_account_id' => 'ea1',
        'type' => 'sepa_core', 'scheme' => 'sepa',
        'status' => 'active', 'sequence_type' => 'recurrent',
        'reference' => 'MNDREF-001', 'unique_mandate_reference' => 'UMR-1',
        'creditor_identifier' => 'FR00ZZZ123456',
        'signature_date' => '2026-01-15', 'signature_location' => 'Paris',
        'creditor' => { 'name' => 'Acme SAS' },
        'debtor' => { 'name' => 'Jane Doe' },
        'debtor_account' => { 'account_number' => 'FR..' },
        'amendment_information' => nil,
        'custom_fields' => {}, 'metadata' => {},
        'created_at' => '2026-01-15T08:50:28Z'
      }
    end

    before do
      allow(datasource).to receive(:get_collection).with('MambuConnectedAccount').and_return(ca_collection)
      allow(datasource).to receive(:get_collection).with('MambuExternalAccount').and_return(ea_collection)
    end

    describe 'schema' do
      it 'declares the API-aligned columns' do
        keys = collection.schema[:fields].keys
        expect(keys).to include(
          'id', 'connected_account_id', 'external_account_id', 'type', 'scheme',
          'status', 'sequence_type', 'reference', 'unique_mandate_reference',
          'creditor_identifier', 'signature_date', 'signature_location',
          'creditor', 'debtor', 'debtor_account', 'amendment_information',
          'custom_fields', 'metadata', 'created_at'
        )
      end

      it 'declares ManyToOne to connected_account and external_account' do
        rels = collection.schema[:fields].select do |_, v|
          v.is_a?(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
        end
        expect(rels.keys).to contain_exactly('connected_account', 'external_account')
      end

      it 'exposes sequence_type and scheme as Enum columns with constrained values' do
        f = collection.schema[:fields]
        expect(f['sequence_type'].column_type).to eq('Enum')
        expect(f['sequence_type'].enum_values).to contain_exactly('one_off', 'recurrent', 'first', 'final')
        expect(f['scheme'].column_type).to eq('Enum')
        expect(f['scheme'].enum_values).to contain_exactly('sepa', 'bacs', 'ach')
      end

      it 'keeps creditor / debtor / debtor_account as Json (embedded snapshots)' do
        f = collection.schema[:fields]
        %w[creditor debtor debtor_account].each do |k|
          expect(f[k].column_type).to eq('Json')
        end
      end

      it 'marks system-managed fields as read-only' do
        f = collection.schema[:fields]
        %w[id status created_at].each { |k| expect(f[k].is_read_only).to be(true) }
      end
    end

    describe '#list' do
      it 'returns rows without resolving relations when projection has no relation prefix' do
        allow(client).to receive(:list_direct_debit_mandates).and_return([mandate])
        allow(client).to receive(:find_connected_account)
        allow(client).to receive(:find_external_account)

        rows = collection.list(nil, Filter.new, ['id', 'unique_mandate_reference'])

        expect(rows).to eq([{ 'id' => 'dm1', 'unique_mandate_reference' => 'UMR-1' }])
        expect(client).not_to have_received(:find_connected_account)
        expect(client).not_to have_received(:find_external_account)
      end

      it 'embeds connected_account when requested by the projection' do
        allow(client).to receive(:list_direct_debit_mandates).and_return([mandate])
        allow(client).to receive(:find_connected_account).with('acc1').and_return(account)

        rows = collection.list(nil, Filter.new, ['id', 'connected_account:name'])
        expect(rows.first['connected_account']).to include('name' => 'Acme')
      end

      it 'embeds external_account when requested by the projection' do
        allow(client).to receive(:list_direct_debit_mandates).and_return([mandate])
        allow(client).to receive(:find_external_account).with('ea1').and_return('id' => 'ea1')

        rows = collection.list(nil, Filter.new, ['id', 'external_account:id'])
        expect(rows.first['external_account']).to include('id' => 'ea1')
      end

      it 'short-circuits to find_direct_debit_mandate on id lookup' do
        allow(client).to receive(:find_direct_debit_mandate).with('dm1').and_return(mandate)
        allow(client).to receive(:list_direct_debit_mandates)

        filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 'dm1'))
        collection.list(nil, filter, nil)

        expect(client).to have_received(:find_direct_debit_mandate).with('dm1')
        expect(client).not_to have_received(:list_direct_debit_mandates)
      end
    end

    describe '#create' do
      it 'strips system-managed fields before POSTing' do
        allow(client).to receive(:create_direct_debit_mandate) do |payload|
          expect(payload).to include('unique_mandate_reference' => 'UMR-1')
          expect(payload.keys).not_to include('id', 'object', 'status', 'created_at')
          { 'id' => 'dm1', 'unique_mandate_reference' => 'UMR-1' }
        end

        collection.create(nil,
                          'id' => 'ignored', 'object' => 'direct_debit_mandate',
                          'status' => 'active', 'created_at' => 't',
                          'unique_mandate_reference' => 'UMR-1')

        expect(client).to have_received(:create_direct_debit_mandate)
      end
    end

    describe '#update' do
      it 'PATCHes each id resolved by the filter' do
        allow(client).to receive(:find_direct_debit_mandate).with('a').and_return('id' => 'a')
        allow(client).to receive(:find_direct_debit_mandate).with('b').and_return('id' => 'b')
        allow(client).to receive(:update_direct_debit_mandate)

        collection.update(nil,
                          Filter.new(condition_tree: Leaf.new('id', 'in', %w[a b])),
                          'reference' => 'NEWREF')

        expect(client).to have_received(:update_direct_debit_mandate)
          .with('a', hash_including('reference' => 'NEWREF'))
        expect(client).to have_received(:update_direct_debit_mandate)
          .with('b', hash_including('reference' => 'NEWREF'))
      end
    end

    describe '#delete' do
      it 'DELETEs each id resolved by the filter' do
        allow(client).to receive(:find_direct_debit_mandate).with('a').and_return('id' => 'a')
        allow(client).to receive(:delete_direct_debit_mandate)

        collection.delete(nil, Filter.new(condition_tree: Leaf.new('id', 'equal', 'a')))

        expect(client).to have_received(:delete_direct_debit_mandate).with('a')
      end
    end
  end
end
