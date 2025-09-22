module ForestAdminAgent
  module Http
    module Exceptions
      class UnprocessableError < HttpException
        attr_reader :name

        def initialize(message = '', name = 'UnprocessableError')
          super(422, message, name)
        end
      end
    end
  end
end
