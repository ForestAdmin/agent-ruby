module ForestAdminAgent
  module Http
    module Exceptions
      class AuthenticationOpenIdClient < HttpException
        def initialize(message = 'Authentication failed with OpenID Client',
                       name = 'AuthenticationOpenIdClient')
          super(401, message, name)
        end
      end
    end
  end
end
