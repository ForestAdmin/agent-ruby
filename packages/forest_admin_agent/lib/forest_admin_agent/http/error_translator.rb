require_relative 'Exceptions/business_error'
require_relative 'Exceptions/http_error'

module ForestAdminAgent
  module Http
    class ErrorTranslator
      # Translate any exception to its appropriate HTTP error representation
      # @param error [Exception] The error to translate
      # @return [HttpException] The translated error with HTTP-specific properties
      #
      # This method handles:
      # 1. HttpException → returned as-is (already have status info)
      # 2. DatasourceToolkit ValidationError → Agent ValidationFailedError (400)
      # 3. BusinessError → HttpException (with proper status, headers, metadata)
      # 4. Unknown errors → InternalServerError (500)
      def self.translate(error) # rubocop:disable Metrics/MethodLength
        return error if error.is_a?(Exceptions::HttpException)
        if error.respond_to?(:status) && error.status
          return Exceptions::HttpException.new(error, error.status, error.message)
        end

        if defined?(ForestAdminAgent::Facades) &&
           (customizer = ForestAdminAgent::Facades::Container.cache(:customize_error_message))
          message = eval(customizer).call(error) # rubocop:disable Security/Eval
          return Exceptions::HttpException.new(StandardError.new(message || 'Unexpected error'), 500)
        end

        if defined?(ForestAdminDatasourceToolkit::Exceptions::ValidationError) &&
           error.is_a?(ForestAdminDatasourceToolkit::Exceptions::ValidationError)
          error = Exceptions::ValidationFailedError.new(error.message)
        end

        case error
        when Exceptions::BadRequestError
          Exceptions::HttpException.new(error, 400, 'Bad Request')
        when Exceptions::ForbiddenError
          Exceptions::HttpException.new(error, 403, 'Forbidden')
        when Exceptions::UnauthorizedError
          Exceptions::HttpException.new(error, 401, 'Unauthorized')
        when Exceptions::NotFoundError
          Exceptions::HttpException.new(error, 404, 'Not Found', {
                                          custom_headers: lambda { |_error|
                                            { 'x-error-type' => 'object-not-found' }
                                          }
                                        })
        when Exceptions::ConflictError
          Exceptions::HttpException.new(error, 409, 'Conflict')
        when Exceptions::UnprocessableError
          Exceptions::HttpException.new(error, 422, 'Unprocessable Entity')
        when Exceptions::TooManyRequestsError
          Exceptions::HttpException.new(error, 429, 'Too Many Requests', {
                                          custom_headers: lambda { |error|
                                            { 'Retry-After' => error.retry_after.to_s }
                                          }
                                        })
        when Exceptions::InternalServerError
          Exceptions::HttpException.new(error, 500, 'Internal Server Error')
        when Exceptions::BadGatewayError
          Exceptions::HttpException.new(error, 502, 'Bad Gateway')
        when Exceptions::ServiceUnavailableError
          Exceptions::HttpException.new(error, 503, 'Service Unavailable')
        else
          Exceptions::HttpException.new(StandardError.new('Unexpected error'), 500)
        end
      end
    end
  end
end
