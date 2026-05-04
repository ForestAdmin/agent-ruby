RSpec.describe ForestAdminDatasourceZendesk::Collections::User do
  Filter      = ForestAdminDatasourceToolkit::Components::Query::Filter
  Aggregation = ForestAdminDatasourceToolkit::Components::Query::Aggregation
  Leaf        = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  let(:client) { instance_double(ForestAdminDatasourceZendesk::Client) }
  let(:datasource) do
    instance_double(ForestAdminDatasourceZendesk::Datasource,
                    client: client, custom_field_mapping: {})
  end
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
                                    Aggregation.new(operation: 'Count'))

      expect(result).to eq([{ 'value' => 3, 'group' => {} }])
    end

    it 'composes the count query with both filter.condition_tree and filter.search' do
      # Regression: a previous version of the search/count split fed the
      # search term to count() but not to search(), causing the count badge
      # to disagree with the rendered list.
      expect(client).to receive(:count).with('user', query: 'role:admin pierre').and_return(2)

      result = collection.aggregate(nil,
                                    Filter.new(condition_tree: Leaf.new('role', 'equal', 'admin'),
                                               search: 'pierre'),
                                    Aggregation.new(operation: 'Count'))
      expect(result.first['value']).to eq(2)
    end

    it 'list passes the same search term to search() that count() sees' do
      expect(client).to receive(:search) do |type, **opts|
        expect(type).to eq('user')
        expect(opts[:query]).to eq('role:admin pierre')
        []
      end

      collection.list(nil,
                      Filter.new(condition_tree: Leaf.new('role', 'equal', 'admin'), search: 'pierre'),
                      ['id'])
    end

    it 'raises on unsupported aggregations' do
      expect do
        collection.aggregate(nil, Filter.new, Aggregation.new(operation: 'Sum', field: 'id'))
      end.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException)
    end
  end

  describe 'custom fields' do
    let(:cf) do
      [{ column_name: 'tier', zendesk_id: 1, zendesk_key: 'tier',
         schema: ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
           column_type: 'String', filter_operators: [], is_read_only: true
         ) }]
    end
    let(:collection) { described_class.new(datasource, custom_fields: cf) }

    it 'serializes user_fields[key] under the column name' do
      user = zendesk_user('id' => 1, 'user_fields' => { 'tier' => 'gold' })
      expect(client).to receive(:search).and_return([user])

      result = collection.list(nil, Filter.new, nil).first
      expect(result['tier']).to eq('gold')
    end

    it 'folds custom-field columns into user_fields on create' do
      expect(client).to receive(:create_user) do |payload|
        expect(payload).to include('email' => 'a@b.com', 'user_fields' => { 'tier' => 'gold' })
        expect(payload).not_to have_key('tier')
        { 'id' => 1 }
      end
      collection.create(nil, 'email' => 'a@b.com', 'tier' => 'gold')
    end
  end

  describe '#create' do
    it 'POSTs and strips read-only fields from the payload' do
      expect(client).to receive(:create_user) do |payload|
        expect(payload).to include('email' => 'x@y.com', 'name' => 'X')
        expect(payload.keys).not_to include('id', 'created_at', 'updated_at')
        { 'id' => 9, 'email' => 'x@y.com', 'name' => 'X' }
      end

      result = collection.create(nil,
                                 'id' => 999, 'email' => 'x@y.com', 'name' => 'X',
                                 'created_at' => 't', 'updated_at' => 't')
      expect(result['id']).to eq(9)
    end
  end

  describe '#update' do
    it 'PUTs each id resolved by the filter' do
      [3, 4].each do |id|
        allow(client).to receive(:find_user).with(id).and_return(zendesk_user('id' => id))
      end

      expect(client).to receive(:update_user).with(3, hash_including('name' => 'NN'))
      expect(client).to receive(:update_user).with(4, hash_including('name' => 'NN'))

      collection.update(nil,
                        Filter.new(condition_tree: Leaf.new('id', 'in', [3, 4])),
                        'name' => 'NN')
    end
  end

  describe '#delete' do
    it 'DELETEs each id resolved by the filter' do
      allow(client).to receive(:find_user).with(7).and_return(zendesk_user('id' => 7))
      expect(client).to receive(:delete_user).with(7)

      collection.delete(nil, Filter.new(condition_tree: Leaf.new('id', 'equal', 7)))
    end
  end

  describe 'schema writability' do
    it 'marks user-editable fields as writable' do
      f = collection.schema[:fields]
      %w[email name role phone organization_id verified suspended].each do |k|
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
