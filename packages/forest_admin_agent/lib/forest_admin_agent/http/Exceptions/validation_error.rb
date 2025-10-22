require_relative 'http_exception'

module ForestAdminAgent
  module Http
    module Exceptions
      class ValidationError < HttpException
        attr_reader :name

        def initialize(message, name = 'ValidationError')
          super(400, message, name)
        end
      end
    end
  end
end
