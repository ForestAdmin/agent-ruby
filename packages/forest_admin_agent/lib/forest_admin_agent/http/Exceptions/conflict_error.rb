module ForestAdminAgent
  module Http
    module Exceptions
      class ConflictError < HttpException
        attr_reader :name

        def initialize(message, name = 'ConflictError')
          @name = name
          super(429, 'Conflict', message)
        end
      end
    end
  end
end
