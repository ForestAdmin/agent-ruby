module ForestAdminAgent
  module Http
    module Exceptions
      class HttpException < StandardError
        attr_reader :code, :status, :message, :name

        def initialize(code, status, message, name = nil)
          super(message)
          @code = code
          @status = status
          @message = message
          @name = name
        end
      end
    end
  end
end
