module ForestAdminAgent
  module Routes
    module Mcp
      class OauthMetadata < AbstractRoute
        include ForestAdminAgent::Http::Exceptions

        def setup_routes
          add_route(
            'mcp_oauth_metadata',
            'GET',
            '/mcp/.well-known/oauth-authorization-server',
            ->(args) { handle_metadata(args) }
          )

          self
        end

        def handle_metadata(_args = {})
          base_url = Facades::Container.cache(:agent_url) || 'http://localhost:3000/forest'
          forest_server_url = Facades::Container.cache(:forest_server_url)

          {
            content: {
              issuer: base_url,
              authorization_endpoint: "#{base_url}/mcp/oauth/authorize",
              token_endpoint: "#{base_url}/mcp/oauth/token",
              registration_endpoint: "#{forest_server_url}/oauth/register",
              scopes_supported: %w[mcp:read mcp:write mcp:action mcp:admin],
              response_types_supported: ['code'],
              code_challenge_methods_supported: ['S256'],
              token_endpoint_auth_methods_supported: ['none']
            }
          }
        end
      end
    end
  end
end
