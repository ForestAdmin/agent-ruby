module ForestAdminDatasourceIntercom
  RSpec.describe Datasource do
    subject(:datasource) { described_class.new(access_token: 's3cr3t') }

    it 'boots without reaching Intercom' do
      expect { datasource }.not_to raise_error
    end

    # The reference collections come first: they are what turns an assignee id
    # into a teammate and a state id into a label. Conversations follow, Tickets
    # next.
    it 'publishes the collections of the lot' do
      expect(datasource.collections.keys)
        .to eq(%w[IntercomAdmin IntercomTeam IntercomTicketType IntercomTicketState IntercomConversation
                  IntercomTicket])
    end

    # The one read a boot performs: the attributes a workspace declares on its
    # ticket types are columns of the Tickets collection, and a ticket payload
    # carries the values of its own type only, so they cannot be discovered from
    # the records.
    it 'introspects the ticket-type attributes while registering, and reads nothing else' do
      datasource

      expect(WebMock).to have_requested(:get, /ticket_types/).once
      expect(WebMock).not_to have_requested(:get, /conversations|admins|teams/)
    end

    # A token without that permission costs the attribute columns, never the
    # agent.
    it 'boots without the attribute columns when the introspection is refused' do
      allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
      stub_request(:get, /ticket_types/).to_return(status: 403, body: '{}',
                                                   headers: { 'Content-Type' => 'application/json' })

      expect(datasource.get_collection('IntercomTicket').fields.keys).not_to include('_default_title_')
    end

    it 'configures a client from the options it is handed' do
      stub_ticket_types(base: 'https://api.eu.intercom.io')
      configured = described_class.new(access_token: 's3cr3t', region: :eu, rate_limiter: nil)

      expect(configured.configuration.url).to eq('https://api.eu.intercom.io')
      expect(configured.client).to be_a(Client)
    end

    it 'refuses to boot on a configuration it cannot use' do
      expect { described_class.new(access_token: nil) }.to raise_error(ConfigurationError)
    end

    it 'names the collections it holds when printed' do
      expect(datasource.inspect).to include('IntercomAdmin', 'IntercomTicketState')
    end

    it 'never prints the token the client carries' do
      expect(datasource.inspect).not_to include('s3cr3t')
    end
  end
end
