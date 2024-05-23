module ForestAdminAgent
  module Http
    module Exceptions
      class AuthenticationOpenIdClient < HttpException
        attr_reader :error, :message, :state

        def initialize(error, error_description, state)
          super(error, 401, error_description)
          @error = error
          @message = error_description
          @state = state
        end
      end
    end
  end
end
