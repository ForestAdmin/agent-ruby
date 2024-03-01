module ForestAdminAgent
  module Http
    module Exceptions
      class ConflictError < HttpException
        attr_reader :name

        def initialize(message, name = 'ConflictError')
          super(429, message, name)
        end
      end
    end
  end
end
