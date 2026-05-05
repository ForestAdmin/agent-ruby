# Wrapped in `module ForestAdminDatasourceZendesk` so the spec can reference
# Filter / Aggregation / Leaf as bare names without leaking constants into the
# top-level namespace. Same pattern as the active_record specs.
module ForestAdminDatasourceZendesk
  include ForestAdminDatasourceToolkit::Components::Query

  Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  RSpec.describe Collections::Organization do
    let(:client) { instance_double(ForestAdminDatasourceZendesk::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceZendesk::Datasource,
                      client: client, custom_field_mapping: {})
    end
    let(:collection) { described_class.new(datasource) }

    def zendesk_org(attrs)
      Struct.new(:attributes).new(attrs)
    end

    describe 'schema' do
      it 'declares core fields and OneToMany relations to users and tickets' do
        keys = collection.schema[:fields].keys
        expect(keys).to include('id', 'name', 'domain_names', 'users', 'tickets')
        expect(collection.schema[:fields]['users'])
          .to be_a(ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema)
      end
    end

    describe '#list' do
      it 'short-circuits to find_organization on id lookup' do
        org = zendesk_org('id' => 5, 'name' => 'Acme')
        allow(client).to receive_messages(find_organization: org, search: [])

        filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 5))
        expect(collection.list(nil, filter, ['id', 'name']).first['name']).to eq('Acme')
        expect(client).to have_received(:find_organization).with(5)
        expect(client).not_to have_received(:search)
      end

      it 'searches with type:organization otherwise' do
        allow(client).to receive(:search).and_return([])

        filter = Filter.new(condition_tree: Leaf.new('name', 'equal', 'Acme'))
        collection.list(nil, filter, ['id'])
        expect(client).to have_received(:search).with('organization', hash_including(query: 'name:Acme'))
      end
    end

    describe '#aggregate' do
      it 'counts via type:organization' do
        allow(client).to receive(:count).with('organization', query: '').and_return(5)
        result = collection.aggregate(nil, Filter.new, Aggregation.new(operation: 'Count'))
        expect(result.first['value']).to eq(5)
      end

      it 'raises on unsupported aggregations' do
        expect do
          collection.aggregate(nil, Filter.new, Aggregation.new(operation: 'Sum', field: 'id'))
        end.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException)
      end
    end

    describe 'custom fields' do
      let(:cf) do
        [{ column_name: 'plan', zendesk_id: 2, zendesk_key: 'plan',
           schema: ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
             column_type: 'String', filter_operators: [], is_read_only: true
           ) }]
      end
      let(:collection) { described_class.new(datasource, custom_fields: cf) }

      it 'serializes organization_fields[key] under the column name' do
        org = zendesk_org('id' => 1, 'organization_fields' => { 'plan' => 'enterprise' })
        allow(client).to receive(:search).and_return([org])

        result = collection.list(nil, Filter.new, nil).first
        expect(result['plan']).to eq('enterprise')
      end

      it 'folds custom-field columns into organization_fields on create' do
        allow(client).to receive(:create_organization) do |payload|
          expect(payload).to include('name' => 'Acme',
                                     'organization_fields' => { 'plan' => 'enterprise' })
          expect(payload).not_to have_key('plan')
          { 'id' => 1 }
        end
        collection.create(nil, 'name' => 'Acme', 'plan' => 'enterprise')
        expect(client).to have_received(:create_organization)
      end
    end

    describe '#create' do
      it 'POSTs the payload, stripping read-only fields' do
        allow(client).to receive(:create_organization) do |payload|
          expect(payload).to include('name' => 'Acme', 'details' => 'top')
          expect(payload.keys).not_to include('id', 'created_at', 'updated_at')
          { 'id' => 5, 'name' => 'Acme', 'details' => 'top' }
        end

        result = collection.create(nil,
                                   'id' => 999, 'name' => 'Acme', 'details' => 'top',
                                   'created_at' => 't', 'updated_at' => 't')
        expect(result['id']).to eq(5)
        expect(client).to have_received(:create_organization)
      end
    end

    describe '#update' do
      it 'PUTs each id resolved by the filter' do
        [10, 11].each do |id|
          allow(client).to receive(:find_organization).with(id).and_return(zendesk_org('id' => id))
        end
        allow(client).to receive(:update_organization)

        collection.update(nil,
                          Filter.new(condition_tree: Leaf.new('id', 'in', [10, 11])),
                          'details' => 'top')

        expect(client).to have_received(:update_organization).with(10, hash_including('details' => 'top'))
        expect(client).to have_received(:update_organization).with(11, hash_including('details' => 'top'))
      end
    end

    describe '#delete' do
      it 'DELETEs each id resolved by the filter' do
        allow(client).to receive(:find_organization).with(5).and_return(zendesk_org('id' => 5))
        allow(client).to receive(:delete_organization)

        collection.delete(nil, Filter.new(condition_tree: Leaf.new('id', 'equal', 5)))

        expect(client).to have_received(:delete_organization).with(5)
      end
    end

    describe 'schema writability' do
      it 'marks user-editable fields as writable' do
        f = collection.schema[:fields]
        %w[name domain_names details notes group_id shared_tickets].each do |k|
          expect(f[k].is_read_only).to be(false), "#{k} should be writable"
        end
      end

      it 'keeps id and timestamps read-only' do
        f = collection.schema[:fields]
        %w[id created_at updated_at].each do |k|
          expect(f[k].is_read_only).to be(true), "#{k} should be read-only"
        end
      end
    end
  end
end
