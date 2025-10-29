require_relative 'business_error'

module ForestAdminAgent
  module Http
    module Exceptions
      class HttpException < StandardError
        attr_reader :name, :status, :data, :custom_headers

        def initialize(status, name, message, data = {}, custom_headers = {})
          super(message)

          @status = status
          @name = name
          @data = data
          @custom_headers = custom_headers
        end
      end
    end
  end
end
