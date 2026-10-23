module ForestAdminDatasourceIntercom
  RSpec.describe Collections::TicketType do
    subject(:collection) { described_class.new(datasource) }

    # The reference store is off here, and only here: `/ticket_types` is the one
    # reference endpoint the boot also reads -- for the ticket attributes -- so
    # the suite's boot stub would be the answer these examples get, rather than
    # the payload each of them installs. What the store does is covered by
    # `Cache` and by the client, on an endpoint nothing reads at boot.
    let(:datasource) { Datasource.new(access_token: 's3cr3t', rate_limiter: nil, reference_cache_ttl: 0) }
    let(:base) { datasource.configuration.url }

    def filter
      ForestAdminDatasourceToolkit::Components::Query::Filter.new
    end

    def stub_types(*types)
      stub_request(:get, "#{base}/ticket_types")
        .to_return(status: 200, body: { 'type' => 'list', 'data' => types }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'is named IntercomTicketType' do
      expect(collection.name).to eq('IntercomTicketType')
    end

    it 'exposes what makes a ticket type readable' do
      expect(collection.fields.keys).to eq(%w[id name description category icon archived])
    end

    # This endpoint uses the `data` envelope, unlike /admins and /teams.
    it 'reads the endpoint through the data envelope' do
      stub_types('type' => 'ticket_type', 'id' => '1', 'name' => 'Bug', 'description' => 'A bug',
                 'category' => 'request', 'icon' => '🐛', 'archived' => false)

      expect(collection.list(nil, filter, nil))
        .to eq([{ 'id' => '1', 'name' => 'Bug', 'description' => 'A bug', 'category' => 'request',
                  'icon' => '🐛', 'archived' => false }])
    end

    # The attribute definitions nested here are what the ticket collection reads
    # to build its columns -- an attribute of the same name carries a different
    # id from one type to the next -- and they are meaningless as a column.
    it 'leaves the nested attribute definitions out of the schema' do
      stub_types('id' => '1', 'ticket_type_attributes' => { 'type' => 'list', 'data' => [{ 'id' => '9' }] })

      expect(collection.list(nil, filter, nil).first.keys).not_to include('ticket_type_attributes')
    end
  end
end
