require 'spec_helper'

module ForestAdminAgent
  module Auth
    describe OidcClientManager do
      subject(:oidc_client_manager) { described_class.new }

      let(:rendering_id) { 10 }
      let(:oidc_discover_response) { instance_double(OpenIDConnect::Discovery::Provider::Config::Response) }
      let(:oidc_discover_resource) { instance_double(OpenIDConnect::Discovery::Provider::Config::Resource) }
      let(:faraday_connection) { instance_double(Faraday::Connection) }

      context 'when then oidc is called and forest api is down' do
        it 'raises an error' do
          class_double(ForestAdminAgent::Auth::OAuth2::OidcConfig, discover!: OpenIDConnect::Discovery::DiscoveryFailed)
          expect do
            oidc_client_manager.make_forest_provider :rendering_id
          end.to raise_error(ForestAdminAgent::Utils::ErrorMessages::SERVER_DOWN)
        end
      end

      context 'when then oidc is called' do
        let(:register) do
          instance_double(Faraday::Response, body: { 'client_id' => 'client_id', 'redirect_uris' => ['redirect_uri'] })
        end

        before do
          allow(OpenIDConnect::Discovery::Provider::Config::Response).to receive(:new)
            .and_return(oidc_discover_response)
          allow(oidc_discover_response).to receive_messages(:expected_issuer= => 'https://api.development.forestadmin.com')
          allow(oidc_discover_response).to receive_messages(validate!: true)
          allow(oidc_discover_response).to receive(:raw)
            .and_return({ 'registration_endpoint' => 'https://api.development.forestadmin.com/oidc/reg' })
          allow(OpenIDConnect::Discovery::Provider::Config::Resource).to receive(:new)
            .and_return(oidc_discover_resource)
          allow(oidc_discover_resource).to receive(:discover!).and_return(oidc_discover_response)
          allow(Faraday::Connection).to receive(:new).and_return(faraday_connection)
          allow(faraday_connection).to receive(:post).and_return(register)
        end

        it 'returns a forest provider on the make_forest_provider method' do
          result = oidc_client_manager.make_forest_provider :rendering_id
          expect(result).to be_a ForestAdminAgent::Auth::OAuth2::ForestProvider
        end

        it 'setups the cache on the setup_cache method' do
          cache_key = "#{Facades::Container.cache(:auth_secret)}-client-data"
          config_agent = ForestAdminAgent::Facades::Container.config_from_cache
          cache = oidc_client_manager.send(:setup_cache, cache_key, config_agent)
          expect(cache).to be_a Hash
          expect(cache.key?(:client_id)).to be true
          expect(cache[:redirect_uri]).to eq 'redirect_uri'
        end
      end
    end
  end
end
