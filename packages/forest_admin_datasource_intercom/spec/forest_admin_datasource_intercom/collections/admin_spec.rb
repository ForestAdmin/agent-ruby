module ForestAdminDatasourceIntercom
  RSpec.describe Collections::Admin do
    subject(:collection) { described_class.new(datasource) }

    let(:datasource) { Datasource.new(access_token: 's3cr3t', rate_limiter: nil) }
    let(:base) { datasource.configuration.url }

    def filter
      ForestAdminDatasourceToolkit::Components::Query::Filter.new
    end

    def stub_admins(*admins)
      stub_request(:get, "#{base}/admins")
        .to_return(status: 200, body: { 'type' => 'admin.list', 'admins' => admins }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'is named IntercomAdmin' do
      expect(collection.name).to eq('IntercomAdmin')
    end

    it 'exposes the columns an ops lead reads before assigning anything' do
      expect(collection.fields.keys)
        .to eq(%w[id name email job_title away_mode_enabled away_mode_reassign has_inbox_seat team_ids])
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
                  'team_ids' => %w[814865] }])
    end

    # Intercom types a team id as a number here and as a string on the team
    # itself; a filter value from Forest always arrives as a string.
    it 'stringifies the ids so both sides of the membership match' do
      stub_admins('id' => 493_881, 'team_ids' => [814_865, 814_866])

      row = collection.list(nil, filter, nil).first

      expect(row['id']).to eq('493881')
      expect(row['team_ids']).to eq(%w[814865 814866])
    end

    it 'reads a teammate with no team as one with no team, not as one with a null' do
      stub_admins('id' => '1', 'team_ids' => nil)

      expect(collection.list(nil, filter, nil).first['team_ids']).to eq([])
    end
  end
end
