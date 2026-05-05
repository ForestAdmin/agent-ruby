RSpec.describe ForestAdminDatasourceZendesk::Configuration do
  let(:valid_args) do
    { subdomain: 'acme', username: 'agent@acme.com/token', token: 'secret' }
  end

  describe '#initialize' do
    it 'accepts valid credentials' do
      config = described_class.new(**valid_args)

      expect(config.subdomain).to eq('acme')
      expect(config.username).to eq('agent@acme.com/token')
      expect(config.token).to eq('secret')
    end

    it 'raises a ConfigurationError when subdomain is nil' do
      expect { described_class.new(**valid_args, subdomain: nil) }
        .to raise_error(ForestAdminDatasourceZendesk::ConfigurationError, /subdomain/)
    end

    it 'raises a ConfigurationError when subdomain is blank' do
      expect { described_class.new(**valid_args, subdomain: '   ') }
        .to raise_error(ForestAdminDatasourceZendesk::ConfigurationError, /subdomain/)
    end

    it 'raises with username when username is missing' do
      expect { described_class.new(**valid_args, username: nil) }
        .to raise_error(ForestAdminDatasourceZendesk::ConfigurationError, /username/)
    end

    it 'raises with token when token is missing' do
      expect { described_class.new(**valid_args, token: '') }
        .to raise_error(ForestAdminDatasourceZendesk::ConfigurationError, /token/)
    end

    it 'lists every missing field at once' do
      expect { described_class.new(subdomain: nil, username: '', token: nil) }
        .to raise_error(ForestAdminDatasourceZendesk::ConfigurationError) { |e|
          expect(e.message).to include('subdomain', 'username', 'token')
        }
    end
  end

  describe '#url' do
    it 'composes the API base URL from the subdomain' do
      config = described_class.new(**valid_args)
      expect(config.url).to eq('https://acme.zendesk.com/api/v2')
    end
  end
end
