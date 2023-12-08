require 'filecache'
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
        cache = FileCache.new('auth_issuer', (config_agent[:cache_dir]).to_s, TTL)
        cache.get_or_set env_secret do
          oidc_config = retrieve_config(config_agent[:forest_server_url])
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

      def retrieve_config(uri)
        OAuth2::OidcConfig.discover! uri
      rescue OpenIDConnect::Discovery::DiscoveryFailed
        raise Error, ForestAdminAgent::Utils::ErrorMessages::SERVER_DOWN
      end
    end
  end
end
