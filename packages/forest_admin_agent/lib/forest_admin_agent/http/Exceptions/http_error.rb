require_relative 'business_error'

module ForestAdminAgent
  module Http
    module Exceptions
      class HttpException < StandardError
        attr_reader :status, :custom_headers, :meta, :cause, :name

        def initialize(error, status, default_message = nil, _meta = nil, custom_headers_proc = nil)
          super(error.message || default_message)

          @name = error.class.name.split('::').last
          @status = status
          @meta = error.respond_to?(:details) ? error.details : {}
          @cause = error

          @custom_headers = if custom_headers_proc.respond_to?(:call)
                              custom_headers_proc.call(error)
                            else
                              {}
                            end
        end
      end
    end
  end
end
