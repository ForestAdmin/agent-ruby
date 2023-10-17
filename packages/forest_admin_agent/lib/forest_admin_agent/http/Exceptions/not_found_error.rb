module ForestAdminAgent
  module Http
    module Exceptions
      class NotFoundError < StandardError
        def initialize(msg, name = 'NotFoundError')
          super msg
        end
      end
    end
  end
end
