require 'jwt'

module ForestAdminAgent
  module Routes
    module Security
      class Authentication < AbstractRoute
        include ForestAdminAgent::Builder
        def setup_routes
          add_route(
            'forest_authentication',
            'POST',
            '/authentication', ->(args) { handle_authentication(args) }
          )
          add_route(
            'forest_authentication-callback',
            'GET',
            '/authentication/callback', ->(args) { handle_authentication_callback(args) }
          )
          add_route(
            'forest_logout',
            'POST',
            '/authentication/logout', ->(args) { handle_authentication_logout(args) }
          )

          self
        end

        def handle_authentication(args = {})
          # Facades::Whitelist.check_ip(args[:headers]['action_dispatch.remote_ip'].to_s)
          rendering_id = get_and_check_rendering_id args[:params]

          {
            content: {
              authorizationUrl: auth.start(rendering_id)
            }
          }
        end

        def handle_authentication_callback(args = {})
          # Facades::Whitelist.check_ip(args[:headers]['action_dispatch.remote_ip'].to_s)
          token = auth.verify_code_and_generate_token(args[:params])
          token_data = JWT.decode(
            token,
            Facades::Container.cache(:auth_secret),
            true,
            { algorithm: 'HS256' }
          )[0]

          {
            content: {
              token: token,
              tokenData: token_data
            }
          }
        end

        def handle_authentication_logout(_args = {})
          {
            content: nil,
            status: 204
          }
        end

        def auth
          ForestAdminAgent::Auth::AuthManager.new
        end

        protected

        def get_and_check_rendering_id(params)
          raise Error, ForestAdminAgent::Utils::ErrorMessages::MISSING_RENDERING_ID unless params['renderingId']

          begin
            Integer(params['renderingId'])
          rescue ArgumentError
            raise Error, ForestAdminAgent::Utils::ErrorMessages::INVALID_RENDERING_ID
          end

          params['renderingId'].to_i
        end
      end
    end
  end
end
