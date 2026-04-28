RSpec.describe ForestAdminDatasourceZendesk::Collections::Organization do
  Filter      = ForestAdminDatasourceToolkit::Components::Query::Filter
  Aggregation = ForestAdminDatasourceToolkit::Components::Query::Aggregation
  Leaf        = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

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
      expect(client).to receive(:find_organization).with(5).and_return(org)
      expect(client).not_to receive(:search)

      filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 5))
      expect(collection.list(nil, filter, ['id', 'name']).first['name']).to eq('Acme')
    end

    it 'searches with type:organization otherwise' do
      expect(client).to receive(:search) do |type, args|
        expect(type).to eq('organization')
        expect(args[:query]).to eq('name:Acme')
        []
      end

      filter = Filter.new(condition_tree: Leaf.new('name', 'equal', 'Acme'))
      collection.list(nil, filter, ['id'])
    end
  end

  describe '#aggregate' do
    it 'counts via type:organization' do
      expect(client).to receive(:count).with('organization', query: '').and_return(5)
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
      expect(client).to receive(:search).and_return([org])

      result = collection.list(nil, Filter.new, nil).first
      expect(result['plan']).to eq('enterprise')
    end
  end
end
