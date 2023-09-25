require 'openid_connect'
require_relative 'oauth2/oidc_config'
require_relative 'oauth2/forest_provider'

module ForestAdminAgent
  module Auth
    class OidcClientManager
      TTL = 60 * 60 * 24

      def make_forest_provider(rendering_id)
        config_agent = Facades::Container.config_from_cache
        cache_key = "#{config_agent[:env_secret]}-client-data"
        cache = setup_cache(cache_key, config_agent)

        render_provider(cache, rendering_id, config_agent[:env_secret])
      end

      private

      def setup_cache(env_secret, config_agent)
        lightly = Lightly.new(life: TTL, dir: "#{config_agent[:cache_dir]}/issuer")
        lightly.get env_secret do
          oidc_config = OAuth2::OidcConfig.discover! config_agent[:forest_server_url]
          credentials = register(
            config_agent[:env_secret],
            oidc_config.raw['registration_endpoint'],
            {
              token_endpoint_auth_method: 'none',
              registration_endpoint: oidc_config.raw['registration_endpoint'],
              application_type: 'web'
            }
          )

          {
            client_id: credentials['client_id'],
            issuer: oidc_config.raw['issuer'],
            redirect_uri: credentials['redirect_uris'].first
          }
        rescue OpenIDConnect::Discovery::DiscoveryFailed
          raise Error, ForestAdminAgent::Utils::ErrorMessages::SERVER_DOWN
        end
      end

      def register(env_secret, registration_endpoint, data)
        response = OpenIDConnect.http_client.post(
          registration_endpoint,
          data,
          { 'Authorization' => "Bearer #{env_secret}" }
        )

        response.body
      end

      def render_provider(cache, rendering_id, secret)
        OAuth2::ForestProvider.new(
          rendering_id,
          {
            identifier: cache[:client_id],
            redirect_uri: cache[:redirect_uri],
            host: cache[:issuer].to_s.sub(%r{^https?://(www.)?}, ''),
            secret: secret
          }
        )
      end
    end
  end
end
