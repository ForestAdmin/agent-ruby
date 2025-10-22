require 'openid_connect'
require 'json'

module ForestAdminAgent
  module Auth
    class AuthManager
      def initialize
        @oidc = ForestAdminAgent::Auth::OidcClientManager.new
      end

      def start(rendering_id)
        client = @oidc.make_forest_provider rendering_id
        client.authorization_uri({ state: JSON.generate({ renderingId: rendering_id }) })
      end

      def verify_code_and_generate_token(params)
        raise ForestAdminAgent::Http::Exceptions::MissingParameterError, 'state' unless params['state']

        if Facades::Container.cache(:debug)
          OpenIDConnect.http_config do |options|
            options.ssl.verify = false
          end
        end

        rendering_id = get_rendering_id_from_state(params['state'])

        forest_provider = @oidc.make_forest_provider rendering_id
        forest_provider.authorization_code = params['code']
        access_token = forest_provider.access_token! 'none'
        resource_owner = forest_provider.get_resource_owner access_token

        resource_owner.make_jwt
      end

      private

      def get_rendering_id_from_state(state)
        state = JSON.parse(state.tr("'", '"').gsub('=>', ':'))
        unless state.key? 'renderingId'
          raise ForestAdminAgent::Http::Exceptions::BadRequestError.new(
            'Invalid state: missing renderingId',
            details: { state: state }
          )
        end

        begin
          Integer(state['renderingId'])
        rescue ArgumentError
          raise ForestAdminAgent::Http::Exceptions::ValidationFailedError.new(
            'Invalid rendering ID: must be an integer',
            details: { renderingId: state['renderingId'] }
          )
        end

        state['renderingId'].to_i
      end
    end
  end
end
