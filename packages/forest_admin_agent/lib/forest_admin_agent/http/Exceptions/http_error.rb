require_relative 'business_error'

module ForestAdminAgent
  module Http
    module Exceptions
      # HttpError wraps a BusinessError and adds HTTP-specific properties
      class HttpError < StandardError
        attr_reader :status, :user_message, :custom_headers, :meta, :cause, :name

        def initialize(error, status, user_message = nil, _meta = nil, custom_headers_proc = nil)
          super(error.message)

          @name = error.class.name.split('::').last
          @status = status
          @user_message = error.message || user_message
          @meta = error.respond_to?(:details) ? error.details : {}
          @cause = error

          @custom_headers = if custom_headers_proc.respond_to?(:call)
                              custom_headers_proc.call(error)
                            else
                              {}
                            end
        end
      end

      # Factory class to generate HTTP error classes for specific status codes
      class HttpErrorFactory
        def self.create_for_business_error(status, default_message, options = {})
          custom_headers_proc = options[:custom_headers]

          Class.new(HttpError) do
            define_method(:initialize) do |error, user_message = nil, meta = nil|
              super(error, status, user_message || default_message, meta, custom_headers_proc)
            end
          end
        end
      end
    end
  end
end
