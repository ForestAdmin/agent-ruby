require 'spec_helper'

module ForestAdminAgent
  module Mcp
    describe OauthProvider do
      subject(:oauth_provider) { described_class.new(forest_server_url: 'https://api.forestadmin.com') }

      let(:auth_secret) { 'test-auth-secret-key-for-jwt-signing' }
      let(:env_secret) { 'test-env-secret' }
      let(:mock_http_client) { instance_double(Faraday::Connection) }

      before do
        allow(ForestAdminAgent::Facades::Container).to receive(:cache).with(:auth_secret).and_return(auth_secret)
        allow(ForestAdminAgent::Facades::Container).to receive(:cache).with(:env_secret).and_return(env_secret)
        allow(ForestAdminAgent::Facades::Container).to receive(:cache).with(:forest_server_url)
                                                                      .and_return('https://api.forestadmin.com')
        mock_logger = double('Logger', log: nil) # rubocop:disable RSpec/VerifiedDoubles
        allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(mock_logger)
        allow(Faraday).to receive(:new).and_return(mock_http_client)
      end

      describe '#initialize!' do
        context 'when environment endpoint succeeds' do
          let(:success_response) do
            instance_double(
              Faraday::Response,
              success?: true,
              body: { data: { id: '12345', attributes: { api_endpoint: 'https://api.env.forestadmin.com' } } }.to_json
            )
          end

          before do
            allow(mock_http_client).to receive(:get).with('/liana/environment').and_return(success_response)
          end

          it 'fetches and stores environment_id' do
            oauth_provider.initialize!
            expect(oauth_provider.environment_id).to eq(12_345)
          end

          it 'fetches and stores environment_api_endpoint' do
            oauth_provider.initialize!
            expect(oauth_provider.environment_api_endpoint).to eq('https://api.env.forestadmin.com')
          end
        end

        context 'when environment endpoint fails' do
          let(:error_response) { instance_double(Faraday::Response, success?: false, status: 500) }

          before do
            allow(mock_http_client).to receive(:get).with('/liana/environment').and_return(error_response)
          end

          it 'logs warning and continues' do
            mock_logger = double('Logger') # rubocop:disable RSpec/VerifiedDoubles
            allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(mock_logger)
            allow(mock_logger).to receive(:log)

            oauth_provider.initialize!

            expect(mock_logger).to have_received(:log).with('Warn', /Failed to fetch environmentId/)
          end
        end
      end

      describe '#get_client' do
        context 'when client exists' do
          let(:client_data) do
            {
              'client_id' => 'mcp-client-123',
              'client_name' => 'Test MCP Client',
              'redirect_uris' => ['https://client.example.com/callback']
            }
          end
          let(:success_response) do
            instance_double(Faraday::Response, success?: true, body: client_data.to_json)
          end

          before do
            allow(mock_http_client).to receive(:get)
              .with('/oauth/register/mcp-client-123')
              .and_return(success_response)
          end

          it 'returns client data' do
            result = oauth_provider.get_client('mcp-client-123')
            expect(result).to eq(client_data)
          end
        end

        context 'when client does not exist' do
          let(:not_found_response) { instance_double(Faraday::Response, success?: false) }

          before do
            allow(mock_http_client).to receive(:get)
              .with('/oauth/register/unknown')
              .and_return(not_found_response)
          end

          it 'returns nil' do
            result = oauth_provider.get_client('unknown')
            expect(result).to be_nil
          end
        end
      end

      describe '#authorize_url' do
        let(:client) { { 'client_id' => 'mcp-client-123' } }
        let(:params) do
          {
            redirect_uri: 'https://client.example.com/callback',
            code_challenge: 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
            state: 'random-state',
            scopes: %w[mcp:read mcp:write],
            resource: 'https://agent.example.com'
          }
        end
        let(:env_response) do
          instance_double(
            Faraday::Response,
            success?: true,
            body: { data: { id: '100', attributes: { api_endpoint: 'https://api.env.forestadmin.com' } } }.to_json
          )
        end

        before do
          allow(mock_http_client).to receive(:get).with('/liana/environment').and_return(env_response)
          oauth_provider.initialize!
        end

        it 'builds authorization URL with all parameters' do
          url = oauth_provider.authorize_url(client, params)

          expect(url).to start_with('https://app.forestadmin.com/oauth/authorize')
          expect(url).to include('client_id=mcp-client-123')
          expect(url).to include('redirect_uri=')
          expect(url).to include('code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM')
          expect(url).to include('code_challenge_method=S256')
          expect(url).to include('response_type=code')
          expect(url).to include('state=random-state')
          expect(url).to include('environmentId=100')
        end

        it 'joins scopes with + separator' do
          url = oauth_provider.authorize_url(client, params)
          expect(url).to include('scope=mcp%3Aread%2Bmcp%3Awrite')
        end
      end

      describe '#exchange_authorization_code' do
        let(:client) { { 'client_id' => 'mcp-client-123' } }
        let(:token_generator) { instance_double(TokenGenerator) }

        before do
          allow(TokenGenerator).to receive(:new).and_return(token_generator)
          allow(token_generator).to receive(:generate).and_return(
            access_token: 'new-access-token',
            token_type: 'Bearer',
            expires_in: 3600,
            refresh_token: 'new-refresh-token'
          )
        end

        it 'delegates to token generator with correct payload' do
          oauth_provider.exchange_authorization_code(client, 'auth-code', 'verifier', 'https://callback.url')

          expect(token_generator).to have_received(:generate).with(
            client,
            hash_including(
              grant_type: 'authorization_code',
              code: 'auth-code',
              code_verifier: 'verifier',
              redirect_uri: 'https://callback.url',
              client_id: 'mcp-client-123'
            )
          )
        end
      end

      describe '#verify_access_token' do
        let(:valid_payload) do
          {
            'id' => 1,
            'email' => 'user@example.com',
            'rendering_id' => 100,
            'type' => 'access',
            'server_token' => 'forest-server-token',
            'exp' => (Time.now + 3600).to_i
          }
        end
        let(:valid_token) { JWT.encode(valid_payload, auth_secret, 'HS256') }
        let(:env_response) do
          instance_double(
            Faraday::Response,
            success?: true,
            body: { data: { id: '100', attributes: { api_endpoint: 'https://api.env.forestadmin.com' } } }.to_json
          )
        end

        before do
          allow(mock_http_client).to receive(:get).with('/liana/environment').and_return(env_response)
          oauth_provider.initialize!
        end

        context 'with valid access token' do
          it 'returns auth info' do
            result = oauth_provider.verify_access_token(valid_token)

            expect(result[:client_id]).to eq('1')
            expect(result[:scopes]).to eq(%w[mcp:read mcp:write mcp:action])
            expect(result[:extra][:email]).to eq('user@example.com')
            expect(result[:extra][:rendering_id]).to eq(100)
          end

          it 'includes environment_api_endpoint in extra' do
            result = oauth_provider.verify_access_token(valid_token)

            expect(result[:extra][:environment_api_endpoint]).to eq('https://api.env.forestadmin.com')
          end
        end

        context 'with refresh token used as access token' do
          let(:refresh_payload) { valid_payload.merge('type' => 'refresh') }
          let(:refresh_token) { JWT.encode(refresh_payload, auth_secret, 'HS256') }

          it 'raises UnsupportedTokenTypeError' do
            expect do
              oauth_provider.verify_access_token(refresh_token)
            end.to raise_error(UnsupportedTokenTypeError, /Cannot use refresh token as access token/)
          end
        end

        context 'with expired token' do
          let(:expired_payload) { valid_payload.merge('exp' => (Time.now - 3600).to_i) }
          let(:expired_token) { JWT.encode(expired_payload, auth_secret, 'HS256') }

          it 'raises InvalidTokenError' do
            expect do
              oauth_provider.verify_access_token(expired_token)
            end.to raise_error(InvalidTokenError, /expired/)
          end
        end

        context 'with invalid signature' do
          let(:invalid_token) { JWT.encode(valid_payload, 'wrong-secret', 'HS256') }

          it 'raises InvalidTokenError' do
            expect do
              oauth_provider.verify_access_token(invalid_token)
            end.to raise_error(InvalidTokenError, /Invalid token/)
          end
        end

        context 'with malformed token' do
          it 'raises InvalidTokenError' do
            expect do
              oauth_provider.verify_access_token('not-a-valid-jwt')
            end.to raise_error(InvalidTokenError)
          end
        end
      end

      describe '#exchange_refresh_token' do
        let(:client) { { 'client_id' => 'mcp-client-123' } }
        let(:refresh_payload) do
          {
            'id' => 1,
            'client_id' => 'mcp-client-123',
            'type' => 'refresh',
            'server_refresh_token' => 'forest-refresh-token',
            'exp' => (Time.now + 86_400).to_i
          }
        end
        let(:refresh_token) { JWT.encode(refresh_payload, auth_secret, 'HS256') }
        let(:token_generator) { instance_double(TokenGenerator) }

        before do
          allow(TokenGenerator).to receive(:new).and_return(token_generator)
          allow(token_generator).to receive(:generate).and_return(
            access_token: 'new-access-token',
            refresh_token: 'new-refresh-token'
          )
        end

        context 'with valid refresh token' do
          it 'returns new tokens' do
            result = oauth_provider.exchange_refresh_token(client, refresh_token)

            expect(result).to include(access_token: 'new-access-token')
          end

          it 'delegates to token generator with refresh payload' do
            oauth_provider.exchange_refresh_token(client, refresh_token)

            expect(token_generator).to have_received(:generate).with(
              client,
              hash_including(
                grant_type: 'refresh_token',
                refresh_token: 'forest-refresh-token',
                client_id: 'mcp-client-123'
              )
            )
          end
        end

        context 'with access token used as refresh token' do
          let(:access_payload) { refresh_payload.merge('type' => 'access') }
          let(:access_token) { JWT.encode(access_payload, auth_secret, 'HS256') }

          it 'raises UnsupportedTokenTypeError' do
            expect do
              oauth_provider.exchange_refresh_token(client, access_token)
            end.to raise_error(UnsupportedTokenTypeError, /Invalid token type/)
          end
        end

        context 'with refresh token from different client' do
          let(:other_client) { { 'client_id' => 'other-client-456' } }

          it 'raises InvalidClientError' do
            expect do
              oauth_provider.exchange_refresh_token(other_client, refresh_token)
            end.to raise_error(InvalidClientError, /not issued to this client/)
          end
        end
      end
    end
  end
end
