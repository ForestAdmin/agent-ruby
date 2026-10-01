module ForestAdminDatasourceIntercom
  RSpec.describe Collections::TicketState do
    subject(:collection) { described_class.new(datasource) }

    let(:datasource) { Datasource.new(access_token: 's3cr3t', rate_limiter: nil) }
    let(:base) { datasource.configuration.url }

    def filter
      ForestAdminDatasourceToolkit::Components::Query::Filter.new
    end

    def stub_ticket_states(*states)
      stub_request(:get, "#{base}/ticket_states")
        .to_return(status: 200, body: { 'type' => 'list', 'data' => states }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'is named IntercomTicketState' do
      expect(collection.name).to eq('IntercomTicketState')
    end

    # Two labels rather than one: what the support team sees, and what the
    # customer is shown.
    it 'exposes both labels of a state' do
      expect(collection.fields.keys).to eq(%w[id category internal_label external_label archived])
    end

    it 'reads the endpoint and serializes a state' do
      stub_ticket_states('type' => 'ticket_state', 'id' => '3', 'category' => 'submitted',
                         'internal_label' => 'Waiting on triage', 'external_label' => 'We are on it',
                         'archived' => false)

      expect(collection.list(nil, filter, nil))
        .to eq([{ 'id' => '3', 'category' => 'submitted', 'internal_label' => 'Waiting on triage',
                  'external_label' => 'We are on it', 'archived' => false }])
    end
  end
end
