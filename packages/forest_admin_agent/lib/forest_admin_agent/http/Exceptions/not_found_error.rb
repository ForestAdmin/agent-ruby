require_relative 'business_error'

module ForestAdminAgent
  module Http
    module Exceptions
      class NotFoundError < BusinessError
        def initialize(message, details: {})
          super
        end
      end
    end
  end
end
