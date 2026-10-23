module ForestAdminDatasourceIntercom
  RSpec.describe Collections::Team do
    subject(:collection) { datasource.get_collection('IntercomTeam') }

    let(:datasource) { Datasource.new(access_token: 's3cr3t', rate_limiter: nil) }
    let(:base) { datasource.configuration.url }

    def filter(condition_tree: nil)
      ForestAdminDatasourceToolkit::Components::Query::Filter.new(condition_tree: condition_tree)
    end

    def admins_named(name)
      operators = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
        .new('admins:name', operators::EQUAL, name)
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

    it 'is named IntercomTeam' do
      expect(collection.name).to eq('IntercomTeam')
    end

    it 'exposes the team, its teammates by name, and the relation to them' do
      expect(collection.fields.keys).to eq(%w[id name admin_names admins])
    end

    it 'reads the endpoint under its own key and stringifies the ids' do
      stub_teams('type' => 'team', 'id' => '814865', 'name' => 'Support', 'admin_ids' => [493_881])

      expect(collection.list(nil, filter, %w[id name])).to eq([{ 'id' => '814865', 'name' => 'Support' }])
    end

    describe 'the teammates of a team' do
      it 'names them for the whole page in one read, rather than one read per row' do
        stub_teams({ 'id' => '814865', 'name' => 'Support', 'admin_ids' => [493_881, 493_882] },
                   { 'id' => '814866', 'name' => 'Billing', 'admin_ids' => [493_882] })
        stub_admins({ 'id' => '493881', 'name' => 'Alice' }, { 'id' => '493882', 'name' => 'Bruno' })

        expect(collection.list(nil, filter, %w[id admin_names]))
          .to eq([{ 'id' => '814865', 'admin_names' => %w[Alice Bruno] },
                  { 'id' => '814866', 'admin_names' => %w[Bruno] }])
        expect(WebMock).to have_requested(:get, "#{base}/admins").once
      end

      it 'names them when the projection names no column at all' do
        stub_teams('id' => '814865', 'name' => 'Support', 'admin_ids' => [493_881])
        stub_admins('id' => '493881', 'name' => 'Alice')

        expect(collection.list(nil, filter, nil).first['admin_names']).to eq(['Alice'])
      end

      it 'reads nothing when no projection asks for the names' do
        stub_teams('id' => '814865', 'name' => 'Support', 'admin_ids' => [493_881])

        collection.list(nil, filter, %w[id name])

        expect(WebMock).not_to have_requested(:get, "#{base}/admins")
      end

      # A missing permission costs the column, never the page -- and never the
      # relation, which reads the teammates from the other side.
      it 'leaves the names empty when the teammates cannot be read' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_teams('id' => '814865', 'admin_ids' => [493_881])
        stub_request(:get, "#{base}/admins").to_return(json({ 'type' => 'error.list' }, 403))

        expect(collection.list(nil, filter, %w[id admin_names]).first)
          .to eq({ 'id' => '814865', 'admin_names' => [] })
      end
    end

    # Intercom carries the membership on the team and on the teammate both and
    # exposes no resource for the pair, so the many-to-many travels through the
    # membership collection this datasource synthesizes.
    describe 'the relation to the teammates' do
      it 'is a many-to-many through the membership collection' do
        expect(collection.fields['admins'])
          .to have_attributes(type: 'ManyToMany', foreign_collection: 'IntercomAdmin',
                              through_collection: 'IntercomTeamMembership',
                              origin_key: 'team_id', foreign_key: 'admin_id')
      end

      # Intercom exposes no endpoint that writes a membership, and an editable
      # relation would offer an association that could only fail.
      it 'is read-only' do
        expect(collection.fields['admins'].is_read_only).to be(true)
      end

      # What the toolkit looks for on the collection a many-to-many travels
      # through. Without the two, a related list falls back to a filter on the
      # foreign collection that nothing there can answer.
      it 'is reachable from both ends of the membership' do
        utils = ForestAdminDatasourceToolkit::Utils::Collection

        expect(utils.get_through_target(collection, 'admins')).to eq('admin')
        expect(utils.get_through_origin(collection, 'admins')).to eq('team')
      end

      # A many-to-many is published unfilterable, so nothing the interface offers
      # reaches here -- a scope or a segment still can, and it is refused rather
      # than resolved by reading the membership once per value.
      it 'refuses a condition through the membership' do
        stub_teams('id' => '814865', 'admin_ids' => [493_881])

        expect { collection.list(nil, filter(condition_tree: admins_named('Alice')), nil) }
          .to raise_error(UnsupportedOperatorError, /"admins" is not a relation it filters through. It has none/)
      end

      # The path a related list really takes: through the membership, whose own
      # relation towards the teammate is what carries the rows back.
      it 'lists the teammates of one team, through the membership' do
        stub_teams({ 'id' => '814865', 'admin_ids' => [493_881] }, { 'id' => '814866', 'admin_ids' => [493_882] })
        stub_admins({ 'id' => '493881', 'name' => 'Alice' }, { 'id' => '493882', 'name' => 'Bruno' })
        query = ForestAdminDatasourceToolkit::Components::Query

        rows = ForestAdminDatasourceToolkit::Utils::Collection.list_relation(
          collection, %w[814865], 'admins', nil, query::Filter.new, query::Projection.new(%w[id name])
        )

        expect(rows).to eq([{ 'id' => '493881', 'name' => 'Alice' }])
      end

      # `admin_ids` names a teammate `/admins` does not answer -- one who left
      # the workspace, one outside the token's reach, one past the page cap of a
      # large workspace. The membership nests a nil under the relation, which is
      # right on a row an operator reads; unwrapped into a related list it would
      # be a row holding nothing, and the serializer reads a row by key.
      it 'drops a teammate the workspace no longer answers, rather than listing an empty row' do
        stub_teams('id' => '814865', 'admin_ids' => [493_881, 999_999])
        stub_admins('id' => '493881', 'name' => 'Alice')
        query = ForestAdminDatasourceToolkit::Components::Query

        rows = ForestAdminDatasourceToolkit::Utils::Collection.list_relation(
          collection, %w[814865], 'admins', nil, query::Filter.new, query::Projection.new(%w[id name])
        )

        expect(rows).to eq([{ 'id' => '493881', 'name' => 'Alice' }])
      end

      # The membership is handed the columns of the collection the relation
      # reaches, `Filter#nest` prefixing the condition tree and not the sort. It
      # cannot order on them, and says so rather than answering an order it did
      # not honour.
      it 'reports the order it cannot honour on a related list' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_teams('id' => '814865', 'admin_ids' => [493_881, 493_882])
        stub_admins({ 'id' => '493881', 'name' => 'Zoe' }, { 'id' => '493882', 'name' => 'Alice' })
        query = ForestAdminDatasourceToolkit::Components::Query

        ForestAdminDatasourceToolkit::Utils::Collection.list_relation(
          collection, %w[814865], 'admins', nil,
          query::Filter.new(sort: query::Sort.new([{ field: 'name', ascending: true }])),
          query::Projection.new(%w[id name])
        )

        expect(ForestAdminDatasourceIntercom.logger)
          .to have_received(:warn).with(/sort on "name", which it does not carry/)
      end
    end
  end
end
