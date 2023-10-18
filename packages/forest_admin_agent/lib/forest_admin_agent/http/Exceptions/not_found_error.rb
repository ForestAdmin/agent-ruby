module ForestAdminAgent
  module Http
    module Exceptions
      class NotFoundError < StandardError
        attr_reader :name, :status

        def initialize(msg, name = 'NotFoundError')
          super msg
          @name = name
          @status = 404
        end
      end
    end
  end
end
