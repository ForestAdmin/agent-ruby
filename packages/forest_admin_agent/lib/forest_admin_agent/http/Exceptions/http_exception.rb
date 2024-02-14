module ForestAdminAgent
  module Http
    module Exceptions
      class HttpException < StandardError
        attr_reader :status, :message, :name

        def initialize(status, message, name = nil)
          super(message)
          @status = status
          @message = message
          @name = name
        end
      end
    end
  end
end
