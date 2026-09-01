module ForestAdminDatasourceIntercom
  RSpec.describe Collections::Team do
    subject(:collection) { described_class.new(datasource) }

    let(:datasource) { Datasource.new(access_token: 's3cr3t', rate_limiter: nil) }
    let(:base) { datasource.configuration.url }

    def filter
      ForestAdminDatasourceToolkit::Components::Query::Filter.new
    end

    def stub_teams(*teams)
      stub_request(:get, "#{base}/teams")
        .to_return(status: 200, body: { 'type' => 'team.list', 'teams' => teams }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'is named IntercomTeam' do
      expect(collection.name).to eq('IntercomTeam')
    end

    it 'exposes the team and its membership' do
      expect(collection.fields.keys).to eq(%w[id name admin_ids])
    end

    # Intercom carries the membership on the team and on the admin both. Left as
    # a plain list it stays readable on either side; declared as a relation it
    # would give the schema two halves of a many-to-many with no join collection.
    it 'keeps the membership a list rather than a relation' do
      expect(collection.fields['admin_ids'])
        .to have_attributes(type: 'Column', column_type: 'Json', filter_operators: [])
    end

    it 'reads the endpoint under its own key and stringifies the ids' do
      stub_teams('type' => 'team', 'id' => '814865', 'name' => 'Support', 'admin_ids' => [493_881])

      expect(collection.list(nil, filter, nil))
        .to eq([{ 'id' => '814865', 'name' => 'Support', 'admin_ids' => %w[493881] }])
    end
  end
end
