require_relative 'error_translator'
require_relative 'Exceptions/business_error'
require_relative 'Exceptions/http_error'

module ForestAdminAgent
  module Http
    module ErrorHandling
      # Translate any exception to its appropriate HTTP error representation
      # and return all error information needed for response
      # @param error [Exception] The error to translate
      # @return [Hash] Hash containing:
      #   - :status - HTTP status code (Integer)
      #   - :message - Error message for the user (String)
      #   - :name - Error name (String)
      #   - :meta - Error metadata/details (Hash)
      #   - :headers - Custom headers to include in response (Hash)
      def translate_error(error)
        translated = ForestAdminAgent::Http::ErrorTranslator.translate(error)

        {
          status: translated.status,
          message: translated.message,
          name: translated.name,
          meta: translated.meta,
          headers: translated.custom_headers
        }
      end
    end
  end
end
