module ForestAdminAgent
  module Http
    module Exceptions
      class ForbiddenError < HttpException
        attr_reader :name

        def initialize(message, name = 'ForbiddenError')
          super(403, message, name)
        end
      end
    end
  end
end
