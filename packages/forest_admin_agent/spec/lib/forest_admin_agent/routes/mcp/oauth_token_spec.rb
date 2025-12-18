require 'spec_helper'

module ForestAdminAgent
  module Routes
    module Mcp
      describe OauthToken do
        subject(:oauth_token) { described_class.new }

        let(:mock_oauth_provider) { instance_double(ForestAdminAgent::Mcp::OauthProvider) }
        let(:valid_client) do
          {
            'client_id' => 'test-client-id',
            'client_name' => 'Test MCP Client'
          }
        end
        let(:token_response) do
          {
            access_token: 'eyJhbGciOiJIUzI1NiJ9...',
            token_type: 'Bearer',
            expires_in: 3600,
            refresh_token: 'eyJhbGciOiJIUzI1NiJ9...',
            scope: 'mcp:read mcp:write mcp:action'
          }
        end

        before do
          allow(ForestAdminAgent::Mcp::OauthProvider).to receive(:new).and_return(mock_oauth_provider)
          allow(mock_oauth_provider).to receive(:initialize!)
        end

        describe '#setup_routes' do
          it 'adds the mcp_oauth_token route' do
            oauth_token.setup_routes
            expect(oauth_token.routes.keys).to include('mcp_oauth_token')
          end

          it 'configures POST method' do
            oauth_token.setup_routes
            expect(oauth_token.routes['mcp_oauth_token'][:method]).to eq('POST')
          end

          it 'configures correct URI' do
            oauth_token.setup_routes
            expect(oauth_token.routes['mcp_oauth_token'][:uri]).to eq('/mcp/oauth/token')
          end
        end

        describe '#handle_token with authorization_code grant' do
          let(:valid_params) do
            {
              'grant_type' => 'authorization_code',
              'client_id' => 'test-client-id',
              'code' => 'authorization-code-from-server',
              'code_verifier' => 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
              'redirect_uri' => 'https://client.example.com/callback'
            }
          end

          context 'with valid authorization code' do
            before do
              allow(mock_oauth_provider).to receive(:get_client).with('test-client-id').and_return(valid_client)
              allow(mock_oauth_provider).to receive(:exchange_authorization_code).and_return(token_response)
            end

            it 'returns token response' do
              result = oauth_token.handle_token(params: valid_params)

              expect(result[:content]).to eq(token_response)
            end

            it 'exchanges authorization code with correct parameters' do
              oauth_token.handle_token(params: valid_params)

              expect(mock_oauth_provider).to have_received(:exchange_authorization_code).with(
                valid_client,
                'authorization-code-from-server',
                'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
                'https://client.example.com/callback'
              )
            end
          end

          context 'with missing required parameters' do
            it 'raises BadRequestError when client_id is missing' do
              params = valid_params.except('client_id')

              expect do
                oauth_token.handle_token(params: params)
              end.to raise_error(ForestAdminAgent::Http::Exceptions::BadRequestError, 'Missing client_id')
            end

            it 'raises BadRequestError when code is missing' do
              params = valid_params.except('code')

              expect do
                oauth_token.handle_token(params: params)
              end.to raise_error(ForestAdminAgent::Http::Exceptions::BadRequestError, 'Missing code')
            end
          end

          context 'when client does not exist' do
            before do
              allow(mock_oauth_provider).to receive(:get_client).with('unknown-client').and_return(nil)
            end

            it 'raises BadRequestError' do
              params = valid_params.merge('client_id' => 'unknown-client')

              expect do
                oauth_token.handle_token(params: params)
              end.to raise_error(ForestAdminAgent::Http::Exceptions::BadRequestError, 'Client not found')
            end
          end

          context 'when authorization code is invalid' do
            before do
              allow(mock_oauth_provider).to receive(:get_client).and_return(valid_client)
              allow(mock_oauth_provider).to receive(:exchange_authorization_code)
                .and_raise(ForestAdminAgent::Mcp::InvalidTokenError, 'Invalid authorization code')
            end

            it 'returns invalid_grant error' do
              result = oauth_token.handle_token(params: valid_params)

              expect(result[:status]).to eq(400)
              expect(result[:content][:error]).to eq('invalid_grant')
              expect(result[:content][:error_description]).to eq('Invalid authorization code')
            end
          end
        end

        describe '#handle_token with refresh_token grant' do
          let(:valid_params) do
            {
              'grant_type' => 'refresh_token',
              'client_id' => 'test-client-id',
              'refresh_token' => 'eyJhbGciOiJIUzI1NiJ9...'
            }
          end

          context 'with valid refresh token' do
            before do
              allow(mock_oauth_provider).to receive(:get_client).with('test-client-id').and_return(valid_client)
              allow(mock_oauth_provider).to receive(:exchange_refresh_token).and_return(token_response)
            end

            it 'returns new token response' do
              result = oauth_token.handle_token(params: valid_params)

              expect(result[:content]).to eq(token_response)
            end

            it 'exchanges refresh token with correct parameters' do
              oauth_token.handle_token(params: valid_params)

              expect(mock_oauth_provider).to have_received(:exchange_refresh_token).with(
                valid_client,
                'eyJhbGciOiJIUzI1NiJ9...',
                nil
              )
            end

            it 'passes scopes when provided' do
              params = valid_params.merge('scope' => 'mcp:read mcp:write')
              oauth_token.handle_token(params: params)

              expect(mock_oauth_provider).to have_received(:exchange_refresh_token).with(
                valid_client,
                'eyJhbGciOiJIUzI1NiJ9...',
                %w[mcp:read mcp:write]
              )
            end
          end

          context 'with missing required parameters' do
            it 'raises BadRequestError when refresh_token is missing' do
              params = valid_params.except('refresh_token')

              expect do
                oauth_token.handle_token(params: params)
              end.to raise_error(ForestAdminAgent::Http::Exceptions::BadRequestError, 'Missing refresh_token')
            end
          end

          context 'when refresh token is expired' do
            before do
              allow(mock_oauth_provider).to receive(:get_client).and_return(valid_client)
              allow(mock_oauth_provider).to receive(:exchange_refresh_token)
                .and_raise(ForestAdminAgent::Mcp::InvalidTokenError, 'Token has expired')
            end

            it 'returns invalid_grant error' do
              result = oauth_token.handle_token(params: valid_params)

              expect(result[:status]).to eq(400)
              expect(result[:content][:error]).to eq('invalid_grant')
            end
          end

          context 'when refresh token belongs to different client' do
            before do
              allow(mock_oauth_provider).to receive(:get_client).and_return(valid_client)
              allow(mock_oauth_provider).to receive(:exchange_refresh_token)
                .and_raise(ForestAdminAgent::Mcp::InvalidClientError, 'Token was not issued to this client')
            end

            it 'returns invalid_client error with 401 status' do
              result = oauth_token.handle_token(params: valid_params)

              expect(result[:status]).to eq(401)
              expect(result[:content][:error]).to eq('invalid_client')
            end
          end
        end

        describe '#handle_token with unsupported grant_type' do
          it 'raises BadRequestError for unsupported grant type' do
            params = { 'grant_type' => 'client_credentials', 'client_id' => 'test' }

            expect do
              oauth_token.handle_token(params: params)
            end.to raise_error(ForestAdminAgent::Http::Exceptions::BadRequestError, /Unsupported grant_type/)
          end
        end
      end
    end
  end
end
