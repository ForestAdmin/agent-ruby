module ForestAdminAgent
  module Routes
    module Mcp
      class McpEndpoint < AbstractRoute
        include ForestAdminAgent::Http::Exceptions

        def setup_routes
          add_route(
            'mcp_endpoint',
            'POST',
            '/mcp',
            ->(args) { handle_mcp(args) }
          )

          self
        end

        def handle_mcp(args = {})
          # Verify Bearer token
          auth_info = verify_bearer_auth(args)

          # Check required scope
          unless auth_info[:scopes]&.include?('mcp:read')
            raise ForbiddenError, 'Missing required scope: mcp:read'
          end

          # Parse JSON-RPC request from body
          body = args[:params]

          # Handle the case where body is already parsed as params
          request = if body.is_a?(Hash) && body['jsonrpc']
                      body
                    elsif body.is_a?(String)
                      JSON.parse(body)
                    else
                      # Try to get the raw body from headers/request
                      raise BadRequestError, 'Invalid request body'
                    end

          # Validate JSON-RPC format
          unless request['jsonrpc'] == '2.0'
            return {
              content: {
                jsonrpc: '2.0',
                id: request['id'],
                error: {
                  code: -32600,
                  message: 'Invalid Request: missing or invalid jsonrpc version'
                }
              }
            }
          end

          # Handle the MCP protocol request
          result = protocol_handler.handle_request(request, auth_info)

          { content: result }
        rescue JSON::ParserError => e
          {
            content: {
              jsonrpc: '2.0',
              id: nil,
              error: {
                code: -32700,
                message: "Parse error: #{e.message}"
              }
            }
          }
        rescue UnauthorizedError => e
          {
            content: {
              jsonrpc: '2.0',
              id: nil,
              error: {
                code: -32603,
                message: e.message
              }
            },
            status: 401
          }
        rescue ForbiddenError => e
          {
            content: {
              jsonrpc: '2.0',
              id: nil,
              error: {
                code: -32603,
                message: e.message
              }
            },
            status: 403
          }
        end

        private

        def verify_bearer_auth(args)
          auth_header = args.dig(:headers, 'HTTP_AUTHORIZATION')

          unless auth_header
            raise UnauthorizedError, 'Missing authorization header'
          end

          parts = auth_header.split(' ')
          unless parts.length == 2 && parts[0].downcase == 'bearer'
            raise UnauthorizedError, 'Invalid authorization header format'
          end

          token = parts[1]
          oauth_provider.verify_access_token(token)
        rescue ForestAdminAgent::Mcp::OAuthProvider::InvalidTokenError => e
          raise UnauthorizedError, e.message
        rescue ForestAdminAgent::Mcp::OAuthProvider::UnsupportedTokenTypeError => e
          raise UnauthorizedError, e.message
        end

        def oauth_provider
          @oauth_provider ||= begin
            provider = ForestAdminAgent::Mcp::OAuthProvider.new
            provider.initialize!
            provider
          end
        end

        def protocol_handler
          @protocol_handler ||= ForestAdminAgent::Mcp::ProtocolHandler.new
        end
      end
    end
  end
end
