module ForestAdminAgent
  module Routes
    module Mcp
      class OAuthAuthorize < AbstractRoute
        include ForestAdminAgent::Http::Exceptions

        def setup_routes
          add_route(
            'mcp_oauth_authorize',
            'GET',
            '/mcp/oauth/authorize',
            ->(args) { handle_authorize(args) }
          )

          self
        end

        def handle_authorize(args = {})
          params = args[:params]

          # Validate required parameters
          client_id = params['client_id']
          redirect_uri = params['redirect_uri']
          code_challenge = params['code_challenge']
          state = params['state']
          scope = params['scope']
          resource = params['resource']

          raise BadRequestError, 'Missing client_id' unless client_id
          raise BadRequestError, 'Missing redirect_uri' unless redirect_uri
          raise BadRequestError, 'Missing code_challenge' unless code_challenge

          # Validate client exists
          client = oauth_provider.get_client(client_id)
          return error_redirect(redirect_uri, 'invalid_client', 'Client not found', state) unless client

          # Build authorization URL and redirect
          authorize_url = oauth_provider.authorize_url(
            client,
            {
              redirect_uri: redirect_uri,
              code_challenge: code_challenge,
              state: state,
              scopes: scope&.split(/[+ ]/) || [],
              resource: resource
            }
          )

          {
            content: {
              type: 'Redirect',
              url: authorize_url
            },
            status: 302
          }
        rescue StandardError => e
          raise unless redirect_uri

          error_redirect(redirect_uri, 'server_error', e.message, state)
        end

        private

        def error_redirect(redirect_uri, error, error_description, state)
          uri = URI(redirect_uri)
          query_params = URI.decode_www_form(uri.query || '')
          query_params << ['error', error]
          query_params << ['error_description', error_description]
          query_params << ['state', state] if state
          uri.query = URI.encode_www_form(query_params)

          {
            content: {
              type: 'Redirect',
              url: uri.to_s
            },
            status: 302
          }
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
