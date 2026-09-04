module ForestAdminDatasourceIntercom
  RSpec.describe Collections::TeamMembership do
    subject(:collection) { datasource.get_collection('IntercomTeamMembership') }

    let(:datasource) { Datasource.new(access_token: 's3cr3t', rate_limiter: nil) }
    let(:base) { datasource.configuration.url }
    let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }

    def filter(condition_tree: nil)
      ForestAdminDatasourceToolkit::Components::Query::Filter.new(condition_tree: condition_tree)
    end

    def leaf(field, operator, value = nil)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
        .new(field, operator, value)
    end

    def branch(aggregator, *conditions)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
        .new(aggregator, conditions)
    end

    def json(payload, status = 200)
      { status: status, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end

    def stub_teams(*teams)
      stub_request(:get, "#{base}/teams").to_return(json('type' => 'team.list', 'teams' => teams))
    end

    def stub_admins(*admins)
      stub_request(:get, "#{base}/admins").to_return(json('type' => 'admin.list', 'admins' => admins))
    end

    it 'is named IntercomTeamMembership' do
      expect(collection.name).to eq('IntercomTeamMembership')
    end

    it 'exposes the pair and a relation to either side of it' do
      expect(collection.fields.keys).to eq(%w[id team_id admin_id team admin])
    end

    # One record per pair, keyed by both ids: a related list is read over two
    # requests, and a key that changed in between would move the rows under the
    # operator.
    it 'reads one record per pair from the team side alone' do
      stub_teams({ 'id' => '814865', 'name' => 'Support', 'admin_ids' => [493_881, 493_882] },
                 { 'id' => '814866', 'name' => 'Billing', 'admin_ids' => [493_882] })

      expect(collection.list(nil, filter, nil))
        .to eq([{ 'id' => '814865:493881', 'team_id' => '814865', 'admin_id' => '493881' },
                { 'id' => '814865:493882', 'team_id' => '814865', 'admin_id' => '493882' },
                { 'id' => '814866:493882', 'team_id' => '814866', 'admin_id' => '493882' }])
      expect(WebMock).not_to have_requested(:get, "#{base}/admins")
    end

    it 'holds no record for a team nobody belongs to' do
      stub_teams({ 'id' => '814865', 'admin_ids' => [] }, { 'id' => '814866', 'admin_ids' => nil })

      expect(collection.list(nil, filter, nil)).to be_empty
    end

    # Intercom types the id as a number inside `admin_ids` and as a string on the
    # teammate itself: the pair carries the form the other side answers by, or
    # the relation resolves to nothing.
    it 'stringifies both ids' do
      stub_teams('id' => 814_865, 'admin_ids' => [493_881])

      expect(collection.list(nil, filter, nil).first)
        .to eq({ 'id' => '814865:493881', 'team_id' => '814865', 'admin_id' => '493881' })
    end

    describe 'a projection through a relation' do
      it 'nests the teammate under the relation, reading them once for the page' do
        stub_teams('id' => '814865', 'admin_ids' => [493_881, 493_882])
        stub_admins({ 'id' => '493881', 'name' => 'Alice' }, { 'id' => '493882', 'name' => 'Bruno' })

        expect(collection.list(nil, filter, ['id', 'admin:name']))
          .to eq([{ 'id' => '814865:493881', 'admin' => { 'name' => 'Alice', 'id' => '493881' } },
                  { 'id' => '814865:493882', 'admin' => { 'name' => 'Bruno', 'id' => '493882' } }])
        expect(WebMock).to have_requested(:get, "#{base}/admins").once
      end

      # A teammate who left the workspace is still named by the membership until
      # Intercom drops the pair. The row reads as having no teammate rather than
      # as a broken record.
      it 'nests nothing when the id names no record' do
        stub_teams('id' => '814865', 'admin_ids' => [493_881])
        stub_admins('id' => '493882', 'name' => 'Bruno')

        expect(collection.list(nil, filter, ['id', 'admin:name']).first)
          .to eq({ 'id' => '814865:493881', 'admin' => nil })
      end

      it 'reads no relation the projection did not name' do
        stub_teams('id' => '814865', 'admin_ids' => [493_881])

        collection.list(nil, filter, %w[id team_id])

        expect(WebMock).not_to have_requested(:get, "#{base}/admins")
      end
    end

    # This tier filters in memory, over every record Intercom holds, so a
    # condition through a relation becomes a plain membership on the foreign key
    # -- none of the limits of Intercom's search DSL apply here, nothing going
    # through it.
    describe 'a condition through a relation' do
      it 'keeps the pairs whose teammate the target matched' do
        stub_teams('id' => '814865', 'admin_ids' => [493_881, 493_882])
        stub_admins({ 'id' => '493881', 'name' => 'Alice' }, { 'id' => '493882', 'name' => 'Bruno' })

        rows = collection.list(nil, filter(condition_tree: leaf('admin:name', operators::EQUAL, 'Alice')), %w[id])

        expect(rows).to eq([{ 'id' => '814865:493881' }])
      end

      it 'answers nothing when the target matched no record, rather than everything' do
        stub_teams('id' => '814865', 'admin_ids' => [493_881])
        stub_admins('id' => '493881', 'name' => 'Alice')

        rows = collection.list(nil, filter(condition_tree: leaf('admin:name', operators::EQUAL, 'Zoe')), %w[id])

        expect(rows).to be_empty
      end

      it 'counts the pairs a relation condition keeps, exactly' do
        stub_teams('id' => '814865', 'admin_ids' => [493_881, 493_882])
        stub_admins({ 'id' => '493881', 'name' => 'Alice' }, { 'id' => '493882', 'name' => 'Bruno' })
        aggregation = ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(operation: 'Count')

        rows = collection.aggregate(nil, filter(condition_tree: leaf('admin:name', operators::EQUAL, 'Alice')),
                                    aggregation)

        expect(rows).to eq([{ 'group' => {}, 'value' => 1 }])
      end

      # The shape the agent really builds: a scope, then a segment, then the
      # operator's own filter, one branch at a time.
      it 'keeps a relation condition standing next to a condition on its own column' do
        stub_teams({ 'id' => '814865', 'admin_ids' => [493_881] }, { 'id' => '814866', 'admin_ids' => [493_881] })
        stub_admins('id' => '493881', 'name' => 'Alice')
        tree = branch('And', leaf('team_id', operators::EQUAL, '814866'),
                      leaf('admin:name', operators::EQUAL, 'Alice'))

        expect(collection.list(nil, filter(condition_tree: tree), %w[id]))
          .to eq([{ 'id' => '814866:493881' }])
      end

      # An `and` carrying a condition nothing can satisfy matches nothing itself.
      it 'answers nothing when a relation condition inside an and matches nothing' do
        stub_teams('id' => '814865', 'admin_ids' => [493_881])
        stub_admins('id' => '493881', 'name' => 'Alice')
        tree = branch('And', leaf('team_id', operators::EQUAL, '814865'),
                      leaf('admin:name', operators::EQUAL, 'Zoe'))

        expect(collection.list(nil, filter(condition_tree: tree), %w[id])).to be_empty
      end

      # An `or` drops it and keeps its siblings: what the others name is still
      # named.
      it 'keeps the siblings of a relation condition inside an or' do
        stub_teams({ 'id' => '814865', 'admin_ids' => [493_881] }, { 'id' => '814866', 'admin_ids' => [493_882] })
        stub_admins({ 'id' => '493881', 'name' => 'Alice' }, { 'id' => '493882', 'name' => 'Bruno' })
        tree = branch('Or', leaf('admin:name', operators::EQUAL, 'Zoe'),
                      leaf('team_id', operators::EQUAL, '814866'))

        expect(collection.list(nil, filter(condition_tree: tree), %w[id]))
          .to eq([{ 'id' => '814866:493882' }])
      end

      it 'answers nothing when every branch of an or matches nothing' do
        stub_teams('id' => '814865', 'admin_ids' => [493_881])
        stub_admins('id' => '493881', 'name' => 'Alice')
        tree = branch('Or', leaf('admin:name', operators::EQUAL, 'Zoe'),
                      leaf('admin:name', operators::EQUAL, 'Yann'))

        expect(collection.list(nil, filter(condition_tree: tree), %w[id])).to be_empty
      end

      # The operators a relation condition may carry are the target's own: it is
      # the one that evaluates them, and the one whose refusal is worth reading.
      it 'refuses an operator the target cannot evaluate, naming it' do
        stub_teams('id' => '814865', 'admin_ids' => [493_881])
        stub_admins('id' => '493881', 'name' => 'Alice')

        expect { collection.list(nil, filter(condition_tree: leaf('admin:team_names', operators::EQUAL, 'x')), nil) }
          .to raise_error(UnsupportedOperatorError, /IntercomAdmin cannot filter 'team_names'/)
      end

      it 'refuses a relation it does not declare, naming the ones it has' do
        stub_teams('id' => '814865', 'admin_ids' => [493_881])

        expect { collection.list(nil, filter(condition_tree: leaf('owner:name', operators::EQUAL, 'x')), nil) }
          .to raise_error(UnsupportedOperatorError, /"owner" is not a relation it filters through.*team, admin/m)
      end

      it 'refuses a path reaching through two relations' do
        stub_teams('id' => '814865', 'admin_ids' => [493_881])

        expect { collection.list(nil, filter(condition_tree: leaf('admin:teams:name', operators::EQUAL, 'x')), nil) }
          .to raise_error(UnsupportedOperatorError, /reaches through two relations/)
      end
    end
  end
end
