module ForestAdminAgent
  module Http
    module Exceptions
      class ForbiddenError < HttpException
        attr_reader :name

        def initialize(message, name = 'ForbiddenError')
          @name = name
          super(403, 'Forbidden', message)
        end
      end
    end
  end
end
