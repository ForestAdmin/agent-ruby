module ForestAdminAgent
  module Routes
    module Mcp
      class OAuthToken < AbstractRoute
        include ForestAdminAgent::Http::Exceptions

        def setup_routes
          add_route(
            'mcp_oauth_token',
            'POST',
            '/mcp/oauth/token',
            ->(args) { handle_token(args) }
          )

          self
        end

        def handle_token(args = {})
          params = args[:params]
          grant_type = params['grant_type']

          case grant_type
          when 'authorization_code'
            handle_authorization_code(params)
          when 'refresh_token'
            handle_refresh_token(params)
          else
            raise BadRequestError, "Unsupported grant_type: #{grant_type}"
          end
        rescue ForestAdminAgent::Mcp::InvalidTokenError => e
          {
            content: {
              error: 'invalid_grant',
              error_description: e.message
            },
            status: 400
          }
        rescue ForestAdminAgent::Mcp::InvalidClientError => e
          {
            content: {
              error: 'invalid_client',
              error_description: e.message
            },
            status: 401
          }
        rescue ForestAdminAgent::Mcp::InvalidRequestError => e
          {
            content: {
              error: 'invalid_request',
              error_description: e.message
            },
            status: 400
          }
        rescue ForestAdminAgent::Mcp::UnsupportedTokenTypeError => e
          {
            content: {
              error: 'unsupported_token_type',
              error_description: e.message
            },
            status: 400
          }
        end

        private

        def handle_authorization_code(params)
          client_id = params['client_id']
          code = params['code']
          code_verifier = params['code_verifier']
          redirect_uri = params['redirect_uri']

          raise BadRequestError, 'Missing client_id' unless client_id
          raise BadRequestError, 'Missing code' unless code

          client = oauth_provider.get_client(client_id)
          raise BadRequestError, 'Client not found' unless client

          tokens = oauth_provider.exchange_authorization_code(
            client,
            code,
            code_verifier,
            redirect_uri
          )

          { content: tokens }
        end

        def handle_refresh_token(params)
          client_id = params['client_id']
          refresh_token = params['refresh_token']
          scope = params['scope']

          raise BadRequestError, 'Missing client_id' unless client_id
          raise BadRequestError, 'Missing refresh_token' unless refresh_token

          client = oauth_provider.get_client(client_id)
          raise BadRequestError, 'Client not found' unless client

          scopes = scope&.split(/[+ ]/)
          tokens = oauth_provider.exchange_refresh_token(client, refresh_token, scopes)

          { content: tokens }
        end

        def oauth_provider
          @oauth_provider ||= begin
            provider = ForestAdminAgent::Mcp::OAuthProvider.new
            provider.initialize!
            provider
          end
        end
      end
    end
  end
end
