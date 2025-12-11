require 'spec_helper'

module ForestAdminAgent
  module Routes
    module Mcp
      describe McpEndpoint do
        subject(:mcp_endpoint) { described_class.new }

        let(:mock_oauth_provider) { instance_double(ForestAdminAgent::Mcp::OauthProvider) }
        let(:mock_protocol_handler) { instance_double(ForestAdminAgent::Mcp::ProtocolHandler) }
        let(:valid_auth_info) do
          {
            token: 'valid-access-token',
            client_id: '123',
            expires_at: (Time.now + 3600).to_i,
            scopes: %w[mcp:read mcp:write mcp:action],
            extra: {
              user_id: 1,
              email: 'user@example.com',
              rendering_id: 100
            }
          }
        end

        before do
          allow(ForestAdminAgent::Mcp::OauthProvider).to receive(:new).and_return(mock_oauth_provider)
          allow(mock_oauth_provider).to receive(:initialize!)
          allow(ForestAdminAgent::Mcp::ProtocolHandler).to receive(:new).and_return(mock_protocol_handler)
        end

        describe '#setup_routes' do
          it 'adds the mcp_endpoint route' do
            mcp_endpoint.setup_routes
            expect(mcp_endpoint.routes.keys).to include('mcp_endpoint')
          end

          it 'configures POST method' do
            mcp_endpoint.setup_routes
            expect(mcp_endpoint.routes['mcp_endpoint'][:method]).to eq('POST')
          end

          it 'configures correct URI' do
            mcp_endpoint.setup_routes
            expect(mcp_endpoint.routes['mcp_endpoint'][:uri]).to eq('/mcp')
          end
        end

        describe '#handle_mcp' do
          let(:valid_jsonrpc_request) do
            {
              'jsonrpc' => '2.0',
              'id' => 1,
              'method' => 'tools/list',
              'params' => {}
            }
          end

          context 'with valid authentication and request' do
            before do
              allow(mock_oauth_provider).to receive(:verify_access_token).and_return(valid_auth_info)
              allow(mock_protocol_handler).to receive(:handle_request).and_return(
                { jsonrpc: '2.0', id: 1, result: { tools: [] } }
              )
            end

            it 'processes JSON-RPC request and returns result' do
              result = mcp_endpoint.handle_mcp(
                params: valid_jsonrpc_request,
                headers: { 'HTTP_AUTHORIZATION' => 'Bearer valid-token' }
              )

              expect(result[:content]).to include(jsonrpc: '2.0', id: 1)
            end

            it 'verifies access token from Authorization header' do
              mcp_endpoint.handle_mcp(
                params: valid_jsonrpc_request,
                headers: { 'HTTP_AUTHORIZATION' => 'Bearer my-access-token' }
              )

              expect(mock_oauth_provider).to have_received(:verify_access_token).with('my-access-token')
            end

            it 'passes auth_info to protocol handler' do
              mcp_endpoint.handle_mcp(
                params: valid_jsonrpc_request,
                headers: { 'HTTP_AUTHORIZATION' => 'Bearer valid-token' }
              )

              expect(mock_protocol_handler).to have_received(:handle_request).with(
                valid_jsonrpc_request,
                valid_auth_info
              )
            end
          end

          context 'with missing authorization header' do
            it 'returns 401 error' do
              result = mcp_endpoint.handle_mcp(
                params: valid_jsonrpc_request,
                headers: {}
              )

              expect(result[:status]).to eq(401)
              expect(result[:content][:error][:message]).to include('Missing authorization header')
            end
          end

          context 'with invalid authorization header format' do
            it 'returns 401 error for missing Bearer prefix' do
              result = mcp_endpoint.handle_mcp(
                params: valid_jsonrpc_request,
                headers: { 'HTTP_AUTHORIZATION' => 'Basic abc123' }
              )

              expect(result[:status]).to eq(401)
              expect(result[:content][:error][:message]).to include('Invalid authorization header format')
            end

            it 'returns 401 error for malformed header' do
              result = mcp_endpoint.handle_mcp(
                params: valid_jsonrpc_request,
                headers: { 'HTTP_AUTHORIZATION' => 'Bearer' }
              )

              expect(result[:status]).to eq(401)
            end
          end

          context 'with invalid access token' do
            before do
              allow(mock_oauth_provider).to receive(:verify_access_token)
                .and_raise(ForestAdminAgent::Mcp::InvalidTokenError, 'Token has expired')
            end

            it 'returns 401 error' do
              result = mcp_endpoint.handle_mcp(
                params: valid_jsonrpc_request,
                headers: { 'HTTP_AUTHORIZATION' => 'Bearer expired-token' }
              )

              expect(result[:status]).to eq(401)
              expect(result[:content][:error][:message]).to eq('Token has expired')
            end
          end

          context 'when using refresh token as access token' do
            before do
              allow(mock_oauth_provider).to receive(:verify_access_token)
                .and_raise(ForestAdminAgent::Mcp::UnsupportedTokenTypeError, 'Cannot use refresh token as access token')
            end

            it 'returns 401 error' do
              result = mcp_endpoint.handle_mcp(
                params: valid_jsonrpc_request,
                headers: { 'HTTP_AUTHORIZATION' => 'Bearer refresh-token' }
              )

              expect(result[:status]).to eq(401)
              expect(result[:content][:error][:message]).to include('refresh token')
            end
          end

          context 'with missing mcp:read scope' do
            let(:auth_info_without_read) do
              valid_auth_info.merge(scopes: %w[mcp:write])
            end

            before do
              allow(mock_oauth_provider).to receive(:verify_access_token).and_return(auth_info_without_read)
            end

            it 'returns 403 error' do
              result = mcp_endpoint.handle_mcp(
                params: valid_jsonrpc_request,
                headers: { 'HTTP_AUTHORIZATION' => 'Bearer valid-token' }
              )

              expect(result[:status]).to eq(403)
              expect(result[:content][:error][:message]).to include('mcp:read')
            end
          end

          context 'with invalid JSON-RPC version' do
            before do
              allow(mock_oauth_provider).to receive(:verify_access_token).and_return(valid_auth_info)
            end

            it 'returns invalid request error for wrong version' do
              invalid_request = valid_jsonrpc_request.merge('jsonrpc' => '1.0')
              result = mcp_endpoint.handle_mcp(
                params: invalid_request,
                headers: { 'HTTP_AUTHORIZATION' => 'Bearer valid-token' }
              )

              expect(result[:content][:error][:code]).to eq(-32_600)
              expect(result[:content][:error][:message]).to include('Invalid Request')
            end

            it 'raises BadRequestError for missing version in hash' do
              invalid_request = valid_jsonrpc_request.except('jsonrpc')

              expect do
                mcp_endpoint.handle_mcp(
                  params: invalid_request,
                  headers: { 'HTTP_AUTHORIZATION' => 'Bearer valid-token' }
                )
              end.to raise_error(ForestAdminAgent::Http::Exceptions::BadRequestError, 'Invalid request body')
            end
          end

          context 'with JSON parse error' do
            before do
              allow(mock_oauth_provider).to receive(:verify_access_token).and_return(valid_auth_info)
            end

            it 'returns parse error for invalid JSON string' do
              result = mcp_endpoint.handle_mcp(
                params: 'invalid json {',
                headers: { 'HTTP_AUTHORIZATION' => 'Bearer valid-token' }
              )

              expect(result[:content][:error][:code]).to eq(-32_700)
              expect(result[:content][:error][:message]).to include('Parse error')
            end
          end
        end
      end
    end
  end
end
