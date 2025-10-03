module ForestAdminAgent
  module Http
    module Exceptions
      class NotFoundError < HttpException
        def initialize(message, name = 'NotFoundError')
          super(404, message, name)
        end
      end
    end
  end
end
