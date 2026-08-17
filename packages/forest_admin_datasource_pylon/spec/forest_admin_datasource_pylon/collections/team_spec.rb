module ForestAdminDatasourcePylon
  RSpec.describe Collections::Team do
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

    # Pylon nests the members as `{id, email}` objects, and a team with none
    # comes back with a null rather than an empty list.
    def team_payload(id, overrides = {})
      { 'id' => id, 'name' => 'Support',
        'users' => [{ 'id' => 'u1', 'email' => 'alice@acme.io' },
                    { 'id' => 'u2', 'email' => 'bob@acme.io' }] }.merge(overrides)
    end

    def stub_teams(*payloads)
      stub_request(:get, "#{base}/teams").to_return(json('data' => payloads))
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
      it 'is named PylonTeam' do
        expect(collection.name).to eq('PylonTeam')
      end

      it 'exposes the columns observed on the API, with the members flattened to their ids' do
        expect(columns.keys).to eq(%w[id name user_ids])
        expect(collection.fields['user_ids'].column_type).to eq('Json')
        expect(collection.fields['id'].column_type).to eq('String')
      end

      it 'declares id as the primary key' do
        expect(collection.fields['id'].is_primary_key).to be(true)
      end

      # Writes land in a later story; the order is honoured in memory over the
      # complete dataset, so both scalar columns can be sorted on.
      it 'declares every column read-only and both scalar columns sortable' do
        expect(columns.values.map(&:is_read_only).uniq).to eq([true])
        expect(columns.except('user_ids').values.map(&:is_sortable).uniq).to eq([true])
        expect(collection.fields['user_ids'].is_sortable).to be(false)
      end

      # GET /teams carries neither a search nor a filter parameter, and Pylon
      # exposes no count.
      it 'leaves search and count disabled' do
        expect(collection.is_searchable?).to be(false)
        expect(collection.is_countable?).to be(false)
      end

      it 'advertises the string filters on the string columns' do
        expect(collection.fields['name'].filter_operators)
          .to eq([operators::EQUAL, operators::NOT_EQUAL, operators::IN, operators::NOT_IN,
                  operators::PRESENT, operators::BLANK, operators::CONTAINS, operators::I_CONTAINS,
                  operators::NOT_CONTAINS, operators::STARTS_WITH, operators::ENDS_WITH])
        expect(collection.fields['id'].filter_operators).to eq(collection.fields['name'].filter_operators)
      end

      # The membership holds a list, whose Pylon semantics have no in-memory
      # counterpart -- and no relation either, see the relations below.
      it 'advertises no filter on the membership' do
        expect(collection.fields['user_ids'].filter_operators).to eq([])
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
      # `/issues/search` filters `team_id` server-side, so the issues assigned to
      # a team are listed by one request.
      it 'declares the issues assigned to a team, read through team_id' do
        expect(collection.fields['issues'])
          .to be_a(ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema)
          .and have_attributes(foreign_collection: 'PylonIssue', origin_key: 'team_id',
                               origin_key_target: 'id')
      end

      # Pylon nests the members here rather than pointing at the team from a
      # user, so the membership is a ManyToMany with no join collection to
      # declare it on: `user_ids` stays a plain column.
      it 'declares no relation for the membership' do
        expect(collection.fields.keys).to eq(%w[id name user_ids issues])
      end
    end

    describe '#list' do
      it 'reads every team of the organization and serializes them' do
        stub_teams(team_payload('t1'), team_payload('t2', 'name' => 'Billing'))

        rows = collection.list(nil, filter, nil)

        expect(ids(rows)).to eq(%w[t1 t2])
        expect(rows.first).to eq('id' => 't1', 'name' => 'Support', 'user_ids' => %w[u1 u2])
      end

      it 'flattens the members to their ids and keeps the nested objects out' do
        stub_teams(team_payload('t1'), team_payload('t2', 'users' => nil))

        rows = collection.list(nil, filter(sort: sort('id')), nil)

        expect(rows.map { |row| row['user_ids'] }).to eq([%w[u1 u2], []])
        expect(rows.first.keys).not_to include('users')
      end

      it 'restricts the record to the projection' do
        stub_teams(team_payload('t1'))

        expect(collection.list(nil, filter, %w[id name])).to eq([{ 'id' => 't1', 'name' => 'Support' }])
      end

      it 'returns an empty list when the organization has no team' do
        stub_teams

        expect(collection.list(nil, filter, nil)).to eq([])
      end

      # Freshness over rate-limit thrift: one call per list, and no record kept
      # from the previous one.
      it 'reads the endpoint once per list, and again on the next one' do
        stub_teams(team_payload('t1'))

        2.times { collection.list(nil, filter, nil) }

        expect(WebMock).to have_requested(:get, "#{base}/teams").twice
      end

      it 'propagates the API error rather than answering with no team' do
        stub_request(:get, "#{base}/teams").to_return(json({ 'message' => 'boom' }, 500))

        expect { collection.list(nil, filter, %w[id]) }.to raise_error(APIError)
      end
    end

    describe '#list with a filter, a sort and a page' do
      before do
        stub_teams(team_payload('t2', 'name' => 'Billing'), team_payload('t1'),
                   team_payload('t3', 'name' => nil, 'users' => []))
      end

      def filtered(field, operator, value = nil)
        ids(collection.list(nil, filter(condition_tree: leaf(field, operator, value)), nil))
      end

      # The single response holds every team, so the filter running in memory
      # answers exactly what a server-side filter would have.
      it 'filters the complete dataset in memory' do
        expect(filtered('name', operators::CONTAINS, 'ill')).to eq(%w[t2])
        expect(filtered('id', operators::IN, %w[t1 t3])).to eq(%w[t1 t3])
        expect(filtered('name', operators::BLANK)).to eq(%w[t3])
      end

      it 'honours the requested order in memory, ascending and descending' do
        expect(ids(collection.list(nil, filter(sort: sort('name')), nil))).to eq(%w[t2 t1 t3])
        expect(ids(collection.list(nil, filter(sort: sort('name', ascending: false)), nil))).to eq(%w[t3 t1 t2])
      end

      it 'honours the ascending primary-key sort the agent injects when nothing is asked for' do
        expect(ids(collection.list(nil, filter(sort: sort('id')), nil))).to eq(%w[t1 t2 t3])
      end

      it 'slices the requested window out of the ordered records' do
        query = filter(sort: sort('id'), page: page(2, 5))

        expect(ids(collection.list(nil, query, %w[id]))).to eq(%w[t3])
      end
    end
  end
end
