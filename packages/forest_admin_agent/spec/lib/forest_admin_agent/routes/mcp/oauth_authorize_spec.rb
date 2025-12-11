require 'spec_helper'

module ForestAdminAgent
  module Routes
    module Mcp
      describe OauthAuthorize do
        subject(:oauth_authorize) { described_class.new }

        let(:mock_oauth_provider) { instance_double(ForestAdminAgent::Mcp::OauthProvider) }
        let(:valid_client) do
          {
            'client_id' => 'test-client-id',
            'client_name' => 'Test MCP Client',
            'redirect_uris' => ['https://client.example.com/callback']
          }
        end

        before do
          allow(ForestAdminAgent::Mcp::OauthProvider).to receive(:new).and_return(mock_oauth_provider)
          allow(mock_oauth_provider).to receive(:initialize!)
        end

        describe '#setup_routes' do
          it 'adds the mcp_oauth_authorize route' do
            oauth_authorize.setup_routes
            expect(oauth_authorize.routes.keys).to include('mcp_oauth_authorize')
          end

          it 'configures GET method' do
            oauth_authorize.setup_routes
            expect(oauth_authorize.routes['mcp_oauth_authorize'][:method]).to eq('GET')
          end

          it 'configures correct URI' do
            oauth_authorize.setup_routes
            expect(oauth_authorize.routes['mcp_oauth_authorize'][:uri]).to eq('/mcp/oauth/authorize')
          end
        end

        describe '#handle_authorize' do
          let(:valid_params) do
            {
              'client_id' => 'test-client-id',
              'redirect_uri' => 'https://client.example.com/callback',
              'code_challenge' => 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
              'state' => 'random-state-value',
              'scope' => 'mcp:read mcp:write'
            }
          end

          context 'with valid parameters' do
            before do
              allow(mock_oauth_provider).to receive(:get_client).with('test-client-id').and_return(valid_client)
              allow(mock_oauth_provider).to receive(:authorize_url).and_return('https://app.forestadmin.com/oauth/authorize?...')
            end

            it 'returns a redirect response' do
              result = oauth_authorize.handle_authorize(params: valid_params)

              expect(result[:status]).to eq(302)
              expect(result[:content][:type]).to eq('Redirect')
            end

            it 'redirects to the ForestAdmin authorization URL' do
              result = oauth_authorize.handle_authorize(params: valid_params)

              expect(result[:content][:url]).to start_with('https://app.forestadmin.com/oauth/authorize')
            end

            it 'calls oauth_provider with correct parameters' do
              oauth_authorize.handle_authorize(params: valid_params)

              expect(mock_oauth_provider).to have_received(:authorize_url).with(
                valid_client,
                hash_including(
                  redirect_uri: 'https://client.example.com/callback',
                  code_challenge: 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
                  state: 'random-state-value',
                  scopes: %w[mcp:read mcp:write]
                )
              )
            end
          end

          context 'with missing required parameters' do
            it 'returns error redirect when client_id is missing' do
              params = valid_params.except('client_id')
              result = oauth_authorize.handle_authorize(params: params)

              expect(result[:status]).to eq(302)
              expect(result[:content][:url]).to include('error=server_error')
              expect(result[:content][:url]).to include('Missing+client_id')
            end

            it 'raises BadRequestError when redirect_uri is missing' do
              params = valid_params.except('redirect_uri')

              expect do
                oauth_authorize.handle_authorize(params: params)
              end.to raise_error(ForestAdminAgent::Http::Exceptions::BadRequestError, 'Missing redirect_uri')
            end

            it 'returns error redirect when code_challenge is missing' do
              params = valid_params.except('code_challenge')
              result = oauth_authorize.handle_authorize(params: params)

              expect(result[:status]).to eq(302)
              expect(result[:content][:url]).to include('error=server_error')
              expect(result[:content][:url]).to include('Missing+code_challenge')
            end
          end

          context 'when client does not exist' do
            before do
              allow(mock_oauth_provider).to receive(:get_client).with('unknown-client').and_return(nil)
            end

            it 'returns error redirect with invalid_client error' do
              params = valid_params.merge('client_id' => 'unknown-client')
              result = oauth_authorize.handle_authorize(params: params)

              expect(result[:status]).to eq(302)
              expect(result[:content][:url]).to include('error=invalid_client')
              expect(result[:content][:url]).to include('error_description=Client+not+found')
            end

            it 'preserves state in error redirect' do
              params = valid_params.merge('client_id' => 'unknown-client')
              result = oauth_authorize.handle_authorize(params: params)

              expect(result[:content][:url]).to include('state=random-state-value')
            end
          end

          context 'when scope is provided with + separator' do
            before do
              allow(mock_oauth_provider).to receive_messages(get_client: valid_client, authorize_url: 'https://example.com')
            end

            it 'correctly parses scopes with + separator' do
              params = valid_params.merge('scope' => 'mcp:read+mcp:write+mcp:action')
              oauth_authorize.handle_authorize(params: params)

              expect(mock_oauth_provider).to have_received(:authorize_url).with(
                valid_client,
                hash_including(scopes: %w[mcp:read mcp:write mcp:action])
              )
            end
          end
        end
      end
    end
  end
end
