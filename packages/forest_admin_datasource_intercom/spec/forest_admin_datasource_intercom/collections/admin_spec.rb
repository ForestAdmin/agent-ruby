module ForestAdminDatasourceIntercom
  RSpec.describe Collections::Admin do
    subject(:collection) { described_class.new(datasource) }

    let(:datasource) { Datasource.new(access_token: 's3cr3t', rate_limiter: nil) }
    let(:base) { datasource.configuration.url }

    def filter
      ForestAdminDatasourceToolkit::Components::Query::Filter.new
    end

    def json(payload, status = 200)
      { status: status, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end

    def stub_admins(*admins)
      stub_request(:get, "#{base}/admins").to_return(json('type' => 'admin.list', 'admins' => admins))
    end

    def stub_teams(*teams)
      stub_request(:get, "#{base}/teams").to_return(json('type' => 'team.list', 'teams' => teams))
    end

    it 'is named IntercomAdmin' do
      expect(collection.name).to eq('IntercomAdmin')
    end

    it 'exposes the columns an ops lead reads before assigning anything' do
      expect(collection.fields.keys)
        .to eq(%w[id name email job_title away_mode_enabled away_mode_reassign has_inbox_seat team_names teams])
    end

    it 'declares id as the primary key' do
      expect(collection.fields['id']).to have_attributes(is_primary_key: true, column_type: 'String')
    end

    # `/admins` puts its records under `admins` rather than under the `data`
    # envelope the paginated listings use.
    it 'reads the endpoint and flattens the teammate' do
      stub_admins('type' => 'admin', 'id' => '1', 'name' => 'Alice', 'email' => 'alice@acme.test',
                  'job_title' => 'Support', 'away_mode_enabled' => true, 'away_mode_reassign' => false,
                  'has_inbox_seat' => true, 'team_ids' => [814_865])

      expect(collection.list(nil, filter, nil))
        .to eq([{ 'id' => '1', 'name' => 'Alice', 'email' => 'alice@acme.test', 'job_title' => 'Support',
                  'away_mode_enabled' => true, 'away_mode_reassign' => false, 'has_inbox_seat' => true,
                  'team_names' => nil }])
    end

    # Intercom types a team id as a number here and as a string on the team
    # itself; a filter value from Forest always arrives as a string. Both sides
    # of the membership therefore carry the same id, without which the relation
    # would resolve to nothing rather than to an error.
    it 'stringifies the ids so both sides of the membership match' do
      stub_admins('id' => 493_881, 'team_ids' => [814_865])
      stub_teams('id' => '814865', 'name' => 'Support')

      expect(collection.list(nil, filter, %w[id team_names]).first)
        .to eq({ 'id' => '493881', 'team_names' => ['Support'] })
    end

    describe 'the teams of a teammate' do
      it 'names them for the whole page in one read, rather than one read per row' do
        stub_admins({ 'id' => '1', 'team_ids' => [814_865] }, { 'id' => '2', 'team_ids' => [814_865, 814_866] })
        stub_teams({ 'id' => '814865', 'name' => 'Support' }, { 'id' => '814866', 'name' => 'Billing' })

        expect(collection.list(nil, filter, %w[id team_names]))
          .to eq([{ 'id' => '1', 'team_names' => ['Support'] },
                  { 'id' => '2', 'team_names' => %w[Support Billing] }])
        expect(WebMock).to have_requested(:get, "#{base}/teams").once
      end

      # A column nobody asked for costs no request.
      it 'reads nothing when no projection asks for the names' do
        stub_admins('id' => '1', 'team_ids' => [814_865])

        collection.list(nil, filter, %w[id name])

        expect(WebMock).not_to have_requested(:get, "#{base}/teams")
      end

      # A missing permission costs the column, never the page -- and never the
      # relation, which reads the teams from the other side.
      it 'leaves the names empty when the teams cannot be read' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_admins('id' => '1', 'team_ids' => [814_865])
        stub_request(:get, "#{base}/teams").to_return(json({ 'type' => 'error.list' }, 403))

        expect(collection.list(nil, filter, %w[id team_names]).first)
          .to eq({ 'id' => '1', 'team_names' => [] })
      end

      it 'reads a teammate with no team as one with no team, not as one with a null' do
        stub_admins('id' => '1', 'team_ids' => nil)
        stub_teams('id' => '814865', 'name' => 'Support')

        expect(collection.list(nil, filter, %w[team_names]).first['team_names']).to eq([])
      end

      it 'is a many-to-many through the membership collection, read-only' do
        expect(collection.fields['teams'])
          .to have_attributes(type: 'ManyToMany', foreign_collection: 'IntercomTeam',
                              through_collection: 'IntercomTeamMembership',
                              origin_key: 'admin_id', foreign_key: 'team_id', is_read_only: true)
      end
    end
  end
end
