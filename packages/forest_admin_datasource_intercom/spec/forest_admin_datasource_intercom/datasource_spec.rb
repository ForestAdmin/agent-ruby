module ForestAdminDatasourceIntercom
  RSpec.describe Datasource do
    subject(:datasource) { described_class.new(access_token: 's3cr3t') }

    it 'boots without reaching Intercom' do
      expect { datasource }.not_to raise_error
    end

    # The reference collections come first: they are what turns an assignee id
    # into a teammate and a state id into a label. Contacts and Companies
    # follow, before the two collections whose relations point at them.
    # The membership sits with the two collections it joins: a many-to-many
    # needs a collection to travel through, and Intercom exposes none.
    it 'publishes the collections of the lot' do
      expect(datasource.collections.keys)
        .to eq(%w[IntercomAdmin IntercomTeam IntercomTeamMembership IntercomTicketType IntercomTicketState
                  IntercomContact IntercomCompany IntercomConversation IntercomTicket])
    end

    # The four reads a boot performs, and no fifth: `/me`, which is where
    # Intercom echoes the API version it served, and the attributes a workspace
    # declares on its ticket types, on its contacts and on its companies --
    # columns of those collections, since a payload carries the values of the
    # attributes that record happens to have been given, never their
    # definitions.
    it 'checks the version and introspects the workspace attributes, and reads nothing else' do
      datasource

      expect(WebMock).to have_requested(:get, %r{/me}).once
      expect(WebMock).to have_requested(:get, /ticket_types/).once
      expect(WebMock).to have_requested(:get, /data_attributes/).with(query: { 'model' => 'contact' }).once
      expect(WebMock).to have_requested(:get, /data_attributes/).with(query: { 'model' => 'company' }).once
      expect(WebMock).not_to have_requested(:get, %r{conversations|admins|teams|companies/list})
    end

    # Intercom serves the workspace's own default when the pin is not honoured
    # and the payload shapes differ between versions. The echo is the only
    # place that shows, and reading it at boot is what turns the check from
    # code that exists into code that runs.
    it 'reports a workspace serving another API version than the pinned one' do
      allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
      stub_me(version: '2.11')

      datasource

      expect(ForestAdminDatasourceIntercom.logger)
        .to have_received(:warn).with(/asked Intercom for API version 2\.16 and it served 2\.11/)
    end

    # Degrades like the attribute reads: a token that cannot reach `/me` costs
    # the check, never the agent.
    it 'boots without the check when the token cannot read /me' do
      allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
      stub_request(:get, %r{/me}).to_return(status: 403, body: '{}',
                                            headers: { 'Content-Type' => 'application/json' })

      expect(datasource.collections.keys).to include('IntercomTicket')
      expect(ForestAdminDatasourceIntercom.logger)
        .to have_received(:warn).with(%r{could not read /me at boot \(HTTP 403\)})
    end

    # A token without that permission costs the attribute columns, never the
    # agent.
    it 'boots without the attribute columns when the introspection is refused' do
      allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
      stub_request(:get, /ticket_types/).to_return(status: 403, body: '{}',
                                                   headers: { 'Content-Type' => 'application/json' })

      expect(datasource.get_collection('IntercomTicket').fields.keys).not_to include('_default_title_')
    end

    # The same guarantee on the other two models, and it is what the acceptance
    # criterion of lot 4 asks for: a token missing a permission costs the
    # columns it could not read, and the collection still boots.
    it 'boots the contact and company collections when their introspection is refused' do
      allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
      stub_request(:get, /data_attributes/).to_return(status: 403, body: '{}',
                                                      headers: { 'Content-Type' => 'application/json' })

      expect(datasource.get_collection('IntercomContact').fields.keys).to include('email')
      expect(datasource.get_collection('IntercomCompany').fields.keys).to include('name')
    end

    it 'configures a client from the options it is handed' do
      stub_me(base: 'https://api.eu.intercom.io')
      stub_ticket_types(base: 'https://api.eu.intercom.io')
      stub_data_attributes('contact', base: 'https://api.eu.intercom.io')
      stub_data_attributes('company', base: 'https://api.eu.intercom.io')
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
