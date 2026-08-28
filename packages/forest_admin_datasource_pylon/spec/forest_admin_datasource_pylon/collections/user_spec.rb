module ForestAdminDatasourcePylon
  RSpec.describe Collections::User do
    def filter(condition_tree: nil, page: nil, sort: nil)
      ForestAdminDatasourceToolkit::Components::Query::Filter.new(
        condition_tree: condition_tree, page: page, sort: sort
      )
    end

    def leaf(field, operator, value = nil)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
        .new(field, operator, value)
    end

    def page(offset, limit)
      ForestAdminDatasourceToolkit::Components::Query::Page.new(offset: offset, limit: limit)
    end

    def sort(field, ascending: true)
      ForestAdminDatasourceToolkit::Components::Query::Sort.new([{ field: field, ascending: ascending }])
    end

    def json(payload, status = 200)
      { status: status, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end

    # Trimmed to the shape observed on the API: `role` is a nested object and an
    # unset value comes back as null rather than absent.
    def user_payload(id, overrides = {})
      {
        'id' => id, 'name' => 'Alice', 'email' => 'alice@acme.io', 'emails' => %w[alice@acme.io a@acme.io],
        'avatar_url' => 'https://cdn.usepylon.com/alice.png', 'status' => 'active', 'role_id' => 'role-1',
        'role' => { 'id' => 'role-1', 'name' => 'Admin', 'slug' => 'admin' }, 'is_deactivated' => false
      }.merge(overrides)
    end

    def stub_users(*payloads)
      stub_request(:get, "#{base}/users").with(query: { 'include_deactivated' => 'true' })
                                         .to_return(json('data' => payloads))
    end

    def ids(records)
      records.map { |record| record['id'] }
    end

    # Mirrors `residual_leaf_appliable?`: an operator is evaluable in memory when
    # `ConditionTreeLeaf#match` handles it natively or the toolkit can rewrite it
    # into operators that it does.
    def appliable?(operator, column_type)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::ConditionTreeEquivalent
        .equivalent_tree?(operator, Collections::BaseCollection::IN_MEMORY_OPERATORS, column_type)
    end

    # Relations are fields too; the assertions on the columns select them out.
    def columns
      collection.fields.select { |_name, field| field.type == 'Column' }
    end

    let(:datasource) { ForestAdminDatasourcePylon::Datasource.new(api_key: 'k') }
    let(:collection) { described_class.new(datasource) }
    let(:base) { datasource.configuration.url }
    let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }

    before { stub_custom_fields }

    describe 'schema' do
      it 'is named PylonUser' do
        expect(collection.name).to eq('PylonUser')
      end

      it 'exposes the columns observed on the API, with the role flattened to its name' do
        expect(columns.keys)
          .to eq(%w[id name email emails avatar_url status role_id role_name is_deactivated])
      end

      it 'declares id as the primary key' do
        expect(collection.fields['id'].is_primary_key).to be(true)
      end

      it 'types the list of addresses as json and the deactivation flag as a boolean' do
        expect(collection.fields['emails'].column_type).to eq('Json')
        expect(collection.fields['is_deactivated'].column_type).to eq('Boolean')
        expect(columns.except('emails', 'is_deactivated').values.map(&:column_type).uniq)
          .to eq(['String'])
      end

      # The order is honoured in memory over the complete dataset, so every
      # scalar column can be sorted on.
      it 'declares every scalar column sortable' do
        expect(columns.except('emails').values.map(&:is_sortable).uniq).to eq([true])
        expect(collection.fields['emails'].is_sortable).to be(false)
      end

      # PATCH /users/{id} takes these four and nothing else: an address is
      # proven by the agent signing in, and the deactivation happens in Pylon.
      it 'declares writable exactly the columns the update endpoint takes' do
        writable = columns.reject { |_name, column| column.is_read_only }.keys

        expect(writable).to contain_exactly('name', 'avatar_url', 'status', 'role_id')
      end

      # GET /users carries no search parameter. It does hand back every agent, so
      # the count is exact rather than a fraction of one.
      it 'leaves search disabled and enables count' do
        expect(collection.is_searchable?).to be(false)
        expect(collection.is_countable?).to be(true)
      end

      it 'advertises the string filters on the string columns' do
        expect(collection.fields['name'].filter_operators)
          .to eq([operators::EQUAL, operators::NOT_EQUAL, operators::IN, operators::NOT_IN,
                  operators::PRESENT, operators::BLANK, operators::CONTAINS, operators::I_CONTAINS,
                  operators::NOT_CONTAINS, operators::STARTS_WITH, operators::ENDS_WITH])
        expect(collection.fields['id'].filter_operators).to eq(collection.fields['name'].filter_operators)
      end

      it 'advertises the boolean filters on the deactivation flag' do
        expect(collection.fields['is_deactivated'].filter_operators)
          .to eq([operators::EQUAL, operators::NOT_EQUAL, operators::IN, operators::NOT_IN,
                  operators::PRESENT, operators::BLANK])
      end

      # The list of addresses has no in-memory filter that would mean what an
      # operator expects, so it advertises none.
      it 'advertises no filter on the list of addresses' do
        expect(collection.fields['emails'].filter_operators).to eq([])
      end

      # Every filter of the schema is answered in memory: one the in-memory pass
      # cannot evaluate would silently empty the page instead of filtering it.
      it 'advertises only operators the in-memory pass can evaluate' do
        unappliable = columns.flat_map do |name, column|
          column.filter_operators.reject { |operator| appliable?(operator, column.column_type) }
                                 .map { |operator| "#{name}: #{operator}" }
        end

        expect(unappliable).to be_empty
      end
    end

    describe 'relations' do
      # `/issues/search` filters `assignee_id` server-side, so the issues of an
      # agent are listed by one request.
      it 'declares the issues assigned to a user, read through assignee_id' do
        expect(collection.fields['assigned_issues'])
          .to be_a(ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema)
          .and have_attributes(foreign_collection: 'PylonIssue', origin_key: 'assignee_id',
                               origin_key_target: 'id')
      end

      # Pylon nests the members inside a team and exposes no team id on a user,
      # so that side is a ManyToMany with no key column to build it on.
      it 'declares no relation to the teams a user belongs to' do
        expect(collection.fields.keys - columns.keys).to eq(%w[assigned_issues])
      end
    end

    describe '#list' do
      it 'reads every user of the organization and serializes them' do
        stub_users(user_payload('u1'), user_payload('u2', 'name' => 'Bob'))

        rows = collection.list(nil, filter, nil)

        expect(ids(rows)).to eq(%w[u1 u2])
        expect(rows.first).to eq('id' => 'u1', 'name' => 'Alice', 'email' => 'alice@acme.io',
                                 'emails' => %w[alice@acme.io a@acme.io], 'status' => 'active',
                                 'avatar_url' => 'https://cdn.usepylon.com/alice.png',
                                 'role_id' => 'role-1', 'role_name' => 'Admin', 'is_deactivated' => false)
      end

      # A deactivated agent stays the assignee of the issues they handled, so the
      # record the rest of the panel points at has to stay readable.
      it 'asks for the deactivated users too' do
        stub_users(user_payload('u1'))

        collection.list(nil, filter, nil)

        expect(WebMock).to have_requested(:get, "#{base}/users")
          .with(query: { 'include_deactivated' => 'true' })
      end

      it 'flattens the nested role and keeps the object out of the record' do
        stub_users(user_payload('u1'), user_payload('u2', 'role' => nil))

        rows = collection.list(nil, filter(sort: sort('id')), nil)

        expect(rows.map { |row| row['role_name'] }).to eq(['Admin', nil])
        expect(rows.first.keys).not_to include('role')
      end

      it 'restricts the record to the projection' do
        stub_users(user_payload('u1'))

        expect(collection.list(nil, filter, %w[id name])).to eq([{ 'id' => 'u1', 'name' => 'Alice' }])
      end

      it 'returns an empty list when the organization has no user' do
        stub_users

        expect(collection.list(nil, filter, nil)).to eq([])
      end

      # Freshness over rate-limit thrift: one call per list, and no record kept
      # from the previous one.
      it 'reads the endpoint once per list, and again on the next one' do
        stub_users(user_payload('u1'))

        2.times { collection.list(nil, filter, nil) }

        expect(WebMock).to have_requested(:get, "#{base}/users")
          .with(query: { 'include_deactivated' => 'true' }).twice
      end
    end

    describe '#list with a filter' do
      before do
        stub_users(user_payload('u1'), user_payload('u2', 'name' => 'Bob', 'is_deactivated' => true),
                   user_payload('u3', 'name' => nil, 'role' => nil, 'avatar_url' => nil))
      end

      def filtered(field, operator, value = nil)
        ids(collection.list(nil, filter(condition_tree: leaf(field, operator, value)), nil))
      end

      # The single response holds every user, so the filter running in memory
      # answers exactly what a server-side filter would have.
      it 'filters the complete dataset in memory' do
        expect(filtered('name', operators::CONTAINS, 'li')).to eq(%w[u1])
        expect(filtered('is_deactivated', operators::EQUAL, true)).to eq(%w[u2])
        expect(filtered('id', operators::IN, %w[u1 u3])).to eq(%w[u1 u3])
      end

      it 'reads the columns Pylon leaves null as blank instead of crashing' do
        expect(filtered('name', operators::BLANK)).to eq(%w[u3])
        expect(filtered('name', operators::CONTAINS, 'li')).to eq(%w[u1])
        expect(filtered('role_name', operators::PRESENT)).to eq(%w[u1 u2])
        expect(filtered('avatar_url', operators::NOT_CONTAINS, 'alice')).to eq(%w[u3])
      end
    end

    describe '#list with a sort and a page' do
      before do
        stub_users(user_payload('u2', 'name' => 'Zoe'), user_payload('u1'),
                   user_payload('u3', 'name' => 'Carol', 'is_deactivated' => true))
      end

      it 'honours the requested order in memory, ascending and descending' do
        expect(ids(collection.list(nil, filter(sort: sort('name')), nil))).to eq(%w[u1 u3 u2])
        expect(ids(collection.list(nil, filter(sort: sort('name', ascending: false)), nil))).to eq(%w[u2 u3 u1])
      end

      it 'honours the ascending primary-key sort the agent injects when nothing is asked for' do
        expect(ids(collection.list(nil, filter(sort: sort('id')), nil))).to eq(%w[u1 u2 u3])
      end

      it 'orders the deactivation flag, false first, the way a database does' do
        expect(ids(collection.list(nil, filter(sort: sort('is_deactivated')), nil))).to eq(%w[u2 u1 u3])
      end

      it 'slices the requested window out of the ordered records' do
        query = filter(sort: sort('id'), page: page(1, 2))

        expect(ids(collection.list(nil, query, %w[id]))).to eq(%w[u2 u3])
      end
    end

    describe '#list when the endpoint fails' do
      it 'propagates the API error rather than answering with no user' do
        stub_request(:get, "#{base}/users").with(query: { 'include_deactivated' => 'true' })
                                           .to_return(json({ 'message' => 'boom' }, 500))

        expect { collection.list(nil, filter, %w[id]) }.to raise_error(APIError)
      end
    end
  end
end
