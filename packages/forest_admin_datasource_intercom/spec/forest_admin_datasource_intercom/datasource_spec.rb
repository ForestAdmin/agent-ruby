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
        .to eq(%w[IntercomAdmin IntercomTeam IntercomTicketType IntercomTicketState IntercomConversation])
    end

    it 'reaches Intercom only when a collection is listed, never while booting' do
      datasource

      expect(WebMock).not_to have_requested(:get, /intercom/)
    end

    it 'configures a client from the options it is handed' do
      configured = described_class.new(access_token: 's3cr3t', region: :eu)

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
