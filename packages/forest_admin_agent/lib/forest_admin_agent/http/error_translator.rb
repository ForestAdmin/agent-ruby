require_relative 'exceptions/business_error'
require_relative 'exceptions/http_error'
require_relative 'exceptions/validation_error'

module ForestAdminAgent
  module Http
    # Translates exceptions to their appropriate HTTP error representation
    # This is the single source of truth for error translation in the agent
    class ErrorTranslator
      # Create specific HTTP error classes for each status code
      ERROR_400 = Exceptions::HttpErrorFactory.create_for_business_error(400, 'Bad Request')
      ERROR_401 = Exceptions::HttpErrorFactory.create_for_business_error(401, 'Unauthorized')
      ERROR_402 = Exceptions::HttpErrorFactory.create_for_business_error(402, 'Payment Required')
      ERROR_403 = Exceptions::HttpErrorFactory.create_for_business_error(403, 'Forbidden')
      ERROR_404 = Exceptions::HttpErrorFactory.create_for_business_error(404, 'Not Found', {
                                                                           custom_headers: lambda { |_error|
                                                                             { 'x-error-type' => 'object-not-found' }
                                                                           }
                                                                         })
      ERROR_409 = Exceptions::HttpErrorFactory.create_for_business_error(409, 'Conflict')
      ERROR_413 = Exceptions::HttpErrorFactory.create_for_business_error(413, 'Content too large')
      ERROR_422 = Exceptions::HttpErrorFactory.create_for_business_error(422, 'Unprocessable Entity')
      ERROR_424 = Exceptions::HttpErrorFactory.create_for_business_error(424, 'Failed Dependency')
      ERROR_425 = Exceptions::HttpErrorFactory.create_for_business_error(425, 'Too Early')
      ERROR_429 = Exceptions::HttpErrorFactory.create_for_business_error(429, 'Too Many Requests', {
                                                                           custom_headers: lambda { |error|
                                                                             { 'Retry-After' => error.retry_after.to_s }
                                                                           }
                                                                         })
      ERROR_451 = Exceptions::HttpErrorFactory.create_for_business_error(451, 'Unavailable For Legal Reasons')
      ERROR_500 = Exceptions::HttpErrorFactory.create_for_business_error(500, 'Internal Server Error')
      ERROR_502 = Exceptions::HttpErrorFactory.create_for_business_error(502, 'Bad Gateway Error')
      ERROR_503 = Exceptions::HttpErrorFactory.create_for_business_error(503, 'Service Unavailable Error')

      # Translate any exception to its appropriate HTTP error representation
      # @param error [Exception] The error to translate
      # @return [HttpError, HttpException, Exception] The translated error or the original error
      #
      # This method handles:
      # 1. HttpError/HttpException → returned as-is (already have status info)
      # 2. DatasourceToolkit ValidationError → Agent ValidationError (HttpException with status 400)
      # 3. BusinessError → HttpError (with proper status, headers, metadata)
      # 4. Unknown errors → returned as-is (will be handled as 500 by error handler)
      def self.translate(error) # rubocop:disable Metrics/MethodLength
        # Already an HttpError or HttpException - no translation needed
        return error if error.is_a?(Exceptions::HttpError)
        return error if error.respond_to?(:status) && error.status

        # Translate DatasourceToolkit ValidationError to Agent ValidationError
        if defined?(ForestAdminDatasourceToolkit::Exceptions::ValidationError) &&
           error.is_a?(ForestAdminDatasourceToolkit::Exceptions::ValidationError)
          return Exceptions::BadRequestError.new(error)
        end

        # Translate BusinessError to HttpError with appropriate status code
        case error
        when Exceptions::BadRequestError
          ERROR_400.new(error)
        when Exceptions::UnauthorizedError
          ERROR_401.new(error)
        when Exceptions::PaymentRequiredError
          ERROR_402.new(error)
        when Exceptions::NotFoundError
          ERROR_404.new(error)
        when Exceptions::ContentTooLargeError
          ERROR_413.new(error)
        when Exceptions::FailedDependencyError
          ERROR_424.new(error)
        when Exceptions::TooEarlyError
          ERROR_425.new(error)
        when Exceptions::TooManyRequestsError
          ERROR_429.new(error)
        when Exceptions::UnavailableForLegalReasonsError
          ERROR_451.new(error)
        when Exceptions::InternalServerError
          ERROR_500.new(error)
        when Exceptions::BadGatewayError
          ERROR_502.new(error)
        when Exceptions::ServiceUnavailableError
          ERROR_503.new(error)
        else
          # Unknown error type - return as-is, will be handled as 500
          error
        end
      end
    end
  end
end
