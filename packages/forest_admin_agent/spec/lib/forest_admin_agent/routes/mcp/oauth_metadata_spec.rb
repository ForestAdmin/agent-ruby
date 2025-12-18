require 'spec_helper'

module ForestAdminAgent
  module Routes
    module Mcp
      describe OauthMetadata do
        subject(:oauth_metadata) { described_class.new }

        describe '#setup_routes' do
          it 'adds the mcp_oauth_metadata route' do
            oauth_metadata.setup_routes
            expect(oauth_metadata.routes.keys).to include('mcp_oauth_metadata')
          end

          it 'configures GET method' do
            oauth_metadata.setup_routes
            expect(oauth_metadata.routes['mcp_oauth_metadata'][:method]).to eq('GET')
          end

          it 'configures correct URI' do
            oauth_metadata.setup_routes
            expect(oauth_metadata.routes['mcp_oauth_metadata'][:uri]).to eq('/mcp/.well-known/oauth-authorization-server')
          end
        end

        describe '#handle_metadata' do
          before do
            allow(ForestAdminAgent::Facades::Container).to receive(:cache).with(:agent_url)
                                                                          .and_return('https://my-agent.example.com/forest')
            allow(ForestAdminAgent::Facades::Container).to receive(:cache).with(:forest_server_url)
                                                                          .and_return('https://api.forestadmin.com')
          end

          it 'returns OAuth 2.0 authorization server metadata' do
            result = oauth_metadata.handle_metadata

            expect(result[:content]).to include(
              issuer: 'https://my-agent.example.com/forest',
              authorization_endpoint: 'https://my-agent.example.com/forest/mcp/oauth/authorize',
              token_endpoint: 'https://my-agent.example.com/forest/mcp/oauth/token',
              registration_endpoint: 'https://api.forestadmin.com/oauth/register'
            )
          end

          it 'includes supported scopes' do
            result = oauth_metadata.handle_metadata

            expect(result[:content][:scopes_supported]).to eq(%w[mcp:read mcp:write mcp:action mcp:admin])
          end

          it 'includes supported response types' do
            result = oauth_metadata.handle_metadata

            expect(result[:content][:response_types_supported]).to eq(['code'])
          end

          it 'includes S256 as supported code challenge method (PKCE)' do
            result = oauth_metadata.handle_metadata

            expect(result[:content][:code_challenge_methods_supported]).to eq(['S256'])
          end

          it 'indicates no client authentication required at token endpoint' do
            result = oauth_metadata.handle_metadata

            expect(result[:content][:token_endpoint_auth_methods_supported]).to eq(['none'])
          end
        end
      end
    end
  end
end
