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
          auth_info = verify_bearer_auth(args)
          raise ForbiddenError, 'Missing required scope: mcp:read' unless auth_info[:scopes]&.include?('mcp:read')

          request = parse_jsonrpc_request(args[:params])
          return invalid_jsonrpc_response(request['id']) unless request['jsonrpc'] == '2.0'

          result = protocol_handler.handle_request(request, auth_info)
          { content: result }
        rescue JSON::ParserError => e
          jsonrpc_error_response(-32_700, "Parse error: #{e.message}")
        rescue UnauthorizedError => e
          jsonrpc_error_response(-32_603, e.message, 401)
        rescue ForbiddenError => e
          jsonrpc_error_response(-32_603, e.message, 403)
        end

        private

        def parse_jsonrpc_request(body)
          return body if body.is_a?(Hash) && body['jsonrpc']
          return JSON.parse(body) if body.is_a?(String)

          raise BadRequestError, 'Invalid request body'
        end

        def invalid_jsonrpc_response(request_id)
          {
            content: {
              jsonrpc: '2.0',
              id: request_id,
              error: {
                code: -32_600,
                message: 'Invalid Request: missing or invalid jsonrpc version'
              }
            }
          }
        end

        def jsonrpc_error_response(code, message, status = nil)
          response = {
            content: {
              jsonrpc: '2.0',
              id: nil,
              error: { code: code, message: message }
            }
          }
          response[:status] = status if status
          response
        end

        def verify_bearer_auth(args)
          auth_header = args.dig(:headers, 'HTTP_AUTHORIZATION')
          raise UnauthorizedError, 'Missing authorization header' unless auth_header

          parts = auth_header.split
          valid_format = parts.length == 2 && parts[0].downcase == 'bearer'
          raise UnauthorizedError, 'Invalid authorization header format' unless valid_format

          oauth_provider.verify_access_token(parts[1])
        rescue ForestAdminAgent::Mcp::InvalidTokenError,
               ForestAdminAgent::Mcp::UnsupportedTokenTypeError => e
          raise UnauthorizedError, e.message
        end

        def oauth_provider
          @oauth_provider ||= begin
            provider = ForestAdminAgent::Mcp::OauthProvider.new
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
