require 'spec_helper'

module ForestAdminAgent
  module Auth
    describe OidcClientManager do
      subject(:oidc_client_manager) { described_class.new }

      let(:rendering_id) { 10 }
      let(:oidc_discover_response) { instance_double(OpenIDConnect::Discovery::Provider::Config::Response) }

      before do
        agent_factory = ForestAdminAgent::Builder::AgentFactory.instance
        agent_factory.setup(
          {
            auth_secret: 'cba803d01a4d43b55010cab41fa1ea1f1f51a95e',
            env_secret: '89719c6d8e2e2de2694c2f220fe2dbf02d5289487364daf1e4c6b13733ed0cdb',
            is_production: false,
            cache_dir: 'tmp/cache/forest_admin',
            forest_server_url: 'https://api.development.forestadmin.com'
          }
        )
        allow(OpenIDConnect::Discovery::Provider::Config::Response).to receive(:new).and_return(oidc_discover_response)
        allow(oidc_discover_response).to receive(:expected_issuer=).receive_messages('https://api.development.forestadmin.com')
        allow(oidc_discover_response).to receive(:validate!).and_return(true)
        allow(oidc_discover_response).to receive(:raw)
          .receive_messages({ 'registration_endpoint' => 'https://api.development.forestadmin.com/oidc/reg' })
      end

      context 'when testing the OidcClientManager class' do
        it 'returns a forest provider on the make_forest_provider method' do
          result = oidc_client_manager.make_forest_provider :rendering_id
          expect(result).to be_a ForestAdminAgent::Auth::OAuth2::ForestProvider
        end

        it 'setups the cache on the setup_cache method' do
          cache_key = "#{Facades::Container.get(:auth_secret)}-client-data"
          config_agent = ForestAdminAgent::Facades::Container.config_from_cache
          cache = oidc_client_manager.send(:setup_cache, cache_key, config_agent)
          puts cache.inspect
          expect(cache).to be_a Hash
          expect(cache.key?(:client_id)).to be true
          expect(cache[:redirect_uri]).to eq 'http://localhost:3000/forest/authentication/callback'
        end
      end
    end
  end
end
