module ForestAdminAgent
  module Http
    module Exceptions
      class ForbiddenError < HttpException
        def initialize(message = 'Forbidden')
          super 403, 'Forbidden', message
        end
      end
    end
  end
end
