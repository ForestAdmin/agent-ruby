RSpec.describe ForestAdminDatasourceZendesk::Collections::User do
  Filter      = ForestAdminDatasourceToolkit::Components::Query::Filter
  Aggregation = ForestAdminDatasourceToolkit::Components::Query::Aggregation
  Leaf        = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  let(:client)     { instance_double(ForestAdminDatasourceZendesk::Client) }
  let(:datasource) { instance_double(ForestAdminDatasourceZendesk::Datasource, client: client) }
  let(:collection) { described_class.new(datasource) }

  def zendesk_user(attrs)
    Struct.new(:attributes).new(attrs)
  end

  describe 'schema' do
    it 'declares core user fields and relations' do
      keys = collection.schema[:fields].keys
      expect(keys).to include('id', 'email', 'name', 'role', 'organization_id',
                              'organization', 'requested_tickets')
    end
  end

  describe '#list' do
    it 'short-circuits to find_user on id lookup' do
      user = zendesk_user('id' => 7, 'email' => 'a@b.com', 'name' => 'A')
      expect(client).to receive(:find_user).with(7).and_return(user)
      expect(client).not_to receive(:search)

      filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 7))
      result = collection.list(nil, filter, ['id', 'email'])
      expect(result.first).to include('id' => 7, 'email' => 'a@b.com')
    end

    it 'searches with type:user otherwise' do
      expect(client).to receive(:search) do |type, args|
        expect(type).to eq('user')
        expect(args[:query]).to eq('role:admin')
        []
      end

      filter = Filter.new(condition_tree: Leaf.new('role', 'equal', 'admin'))
      collection.list(nil, filter, ['id'])
    end
  end

  describe '#aggregate' do
    it 'returns string-key Count via Zendesk count endpoint with type:user' do
      expect(client).to receive(:count).with('user', query: 'role:admin').and_return(3)

      result = collection.aggregate(nil,
        Filter.new(condition_tree: Leaf.new('role', 'equal', 'admin')),
        Aggregation.new(operation: 'Count')
      )

      expect(result).to eq([{ 'value' => 3, 'group' => {} }])
    end

    it 'raises on unsupported aggregations' do
      expect {
        collection.aggregate(nil, Filter.new, Aggregation.new(operation: 'Sum', field: 'id'))
      }.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException)
    end
  end

  describe 'custom fields' do
    let(:cf) do
      [{ column_name: 'tier', zendesk_id: 1, zendesk_key: 'tier',
         schema: ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
           column_type: 'String', filter_operators: [], is_read_only: true) }]
    end
    let(:collection) { described_class.new(datasource, custom_fields: cf) }

    it 'serializes user_fields[key] under the column name' do
      user = zendesk_user('id' => 1, 'user_fields' => { 'tier' => 'gold' })
      expect(client).to receive(:search).and_return([user])

      result = collection.list(nil, Filter.new, nil).first
      expect(result['tier']).to eq('gold')
    end
  end
end
