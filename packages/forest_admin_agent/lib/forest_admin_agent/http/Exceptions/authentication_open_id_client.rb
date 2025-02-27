module ForestAdminAgent
  module Http
    module Exceptions
      class AuthenticationOpenIdClient < HttpException
        def initialize(status = 401,
                       message = 'Authentication failed with OpenID Client',
                       name = 'AuthenticationOpenIdClient')
          super
        end
      end
    end
  end
end
