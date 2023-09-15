require 'openid_connect'

module ForestAdminAgent
  module Auth
    module OAuth2
      class OidcConfig
        def self.discover!(identifier, cache_options = {})
          uri = URI.parse(identifier)
          Resource.new(uri).discover!(cache_options).tap do |response|
            response.expected_issuer = identifier
            response.validate!
          end
        rescue SWD::Exception, OpenIDConnect::ValidationFailed => e
          raise OpenIDConnect::DiscoveryFailed, e.message
        end

        class Resource < OpenIDConnect::Discovery::Provider::Config::Resource
          def initialize(uri)
            super
            @host = uri.host
            @port = uri.port unless [80, 443].include?(uri.port)
            @path = File.join uri.path, 'oidc/.well-known/openid-configuration'
            attr_missing!
          end
        end
      end
    end
  end
end
