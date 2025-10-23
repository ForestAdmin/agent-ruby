require_relative 'error_translator'
require_relative 'exceptions/business_error'
require_relative 'exceptions/http_error'
require_relative 'exceptions/http_exception'
require_relative 'exceptions/validation_error'

module ForestAdminAgent
  module Http
    module ErrorHandling
      # Get the appropriate error message for an error
      # @param error [Exception] The error to get the message for
      # @return [String] The error message to show to the user
      def get_error_message(error)
        # Handle HttpError instances
        return error.user_message if error.is_a?(ForestAdminAgent::Http::Exceptions::HttpError)

        if error.class.respond_to?(:ancestors) && error.class.ancestors.include?(ForestAdminAgent::Http::Exceptions::HttpException)
          return error.message
        end

        return error.message if error.is_a?(ForestAdminAgent::Http::Exceptions::BusinessError)

        # Handle DatasourceToolkit ValidationError
        if defined?(ForestAdminDatasourceToolkit::Exceptions::ValidationError) &&
           error.is_a?(ForestAdminDatasourceToolkit::Exceptions::ValidationError)
          return error.message
        end

        if defined?(ForestAdminAgent::Facades) &&
           (customizer = ForestAdminAgent::Facades::Container.cache(:customize_error_message))
          message = eval(customizer).call(error)
          return message if message
        end

        'Unexpected error'
      end

      # Get the appropriate HTTP status code for an error
      # @param error [Exception] The error to get the status for
      # @return [Integer] The HTTP status code
      def get_error_status(error)
        return error.status if error.is_a?(ForestAdminAgent::Http::Exceptions::HttpError)

        return error.status if error.respond_to?(:status) && error.status

        if error.is_a?(ForestAdminAgent::Http::Exceptions::BusinessError)
          http_error = ForestAdminAgent::Http::ErrorTranslator.translate(error)
          return http_error.status if http_error
        end

        # Handle DatasourceToolkit ValidationError
        if defined?(ForestAdminDatasourceToolkit::Exceptions::ValidationError) &&
           error.is_a?(ForestAdminDatasourceToolkit::Exceptions::ValidationError)
          return 400
        end

        500
      end

      # Get custom headers for an error
      # @param error [Exception] The error to get headers for
      # @return [Hash] Custom headers to include in the response
      def get_error_headers(error)
        return error.custom_headers if error.is_a?(ForestAdminAgent::Http::Exceptions::HttpError)

        {}
      end

      # Get error metadata/details
      # @param error [Exception] The error to get metadata for
      # @return [Hash] Error metadata
      def get_error_meta(error)
        return error.meta if error.is_a?(ForestAdminAgent::Http::Exceptions::HttpError)

        return error.details if error.is_a?(ForestAdminAgent::Http::Exceptions::BusinessError)

        {}
      end

      # Get the error name
      # @param error [Exception] The error to get the name for
      # @return [String] The error name
      def get_error_name(error)
        return error.name if error.is_a?(ForestAdminAgent::Http::Exceptions::HttpError)

        return error.name if error.is_a?(ForestAdminAgent::Http::Exceptions::BusinessError)

        return error.name if error.respond_to?(:name) && error.name

        error.class.name.split('::').last
      end

      # Translate any exception to its appropriate HTTP error representation
      # This is just a convenient wrapper around ErrorTranslator.translate
      # @param error [Exception] The error to translate
      # @return [HttpError, HttpException, Exception] The translated error or the original error
      def translate_error(error)
        # Delegate all translation logic to ErrorTranslator
        ForestAdminAgent::Http::ErrorTranslator.translate(error)
      end
    end
  end
end
