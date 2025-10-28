require_relative 'Exceptions/business_error'
require_relative 'Exceptions/http_exception'

module ForestAdminAgent
  module Http
    class ErrorTranslator
      # Translate any exception to its appropriate HTTP error representation
      # @param error [Exception] The error to translate
      # @return [HttpException] The translated error with HTTP-specific properties
      def self.translate(error)
        return error if error.is_a?(Exceptions::HttpException)

        name = error.class.name.split('::').last

        status = get_error_status(error)

        message = get_error_message(error)

        data = get_error_data(error)

        custom_headers = get_custom_headers(error)

        Exceptions::HttpException.new(
          status,
          name,
          message,
          data,
          custom_headers
        )
      end

      # Get the HTTP status code for an error
      # @param error [Exception] The error to get status for
      # @return [Integer] The HTTP status code
      def self.get_error_status(error) # rubocop:disable Metrics/MethodLength
        if defined?(ForestAdminDatasourceToolkit::Exceptions::ValidationError) &&
           of_type?(error, ForestAdminDatasourceToolkit::Exceptions::ValidationError)
          return 400
        end

        error.status if error.respond_to?(:status) && error.status

        case error
        when Exceptions::ValidationError, Exceptions::BadRequestError
          400
        when Exceptions::UnauthorizedError
          401
        when Exceptions::ForbiddenError
          403
        when Exceptions::NotFoundError
          404
        when Exceptions::ConflictError
          409
        when Exceptions::UnprocessableError
          422
        when Exceptions::TooManyRequestsError
          429
        when Exceptions::InternalServerError
          500
        when Exceptions::BadGatewayError
          502
        when Exceptions::ServiceUnavailableError
          503
        when Exceptions::BusinessError # rubocop:disable Lint/DuplicateBranch
          # default BusinessError → 422 (Unprocessable Entity)
          422
        else # rubocop:disable Lint/DuplicateBranch
          # Unknown errors → 500 (Internal Server Error)
          500
        end
      end

      # Get the error message
      # @param error [Exception] The error to get message from
      # @return [String] The error message to send to the client
      def self.get_error_message(error)
        # Try custom error message customizer first
        if defined?(ForestAdminAgent::Facades) &&
           (customizer = ForestAdminAgent::Facades::Container.cache(:customize_error_message))
          custom_message = eval(customizer).call(error) # rubocop:disable Security/Eval
          return custom_message if custom_message
        end

        is_known_error = error.is_a?(Exceptions::HttpException) ||
                         error.is_a?(Exceptions::BusinessError) ||
                         (defined?(ForestAdminDatasourceToolkit::Exceptions::ForestException) &&
                          error.is_a?(ForestAdminDatasourceToolkit::Exceptions::ForestException))

        return error.message if is_known_error && error.message

        'Unexpected error'
      end

      # Get error data/metadata
      # @param error [Exception] The error to get data from
      # @return [Hash, nil] The error metadata or nil
      def self.get_error_data(error)
        return error.details if error.is_a?(Exceptions::BusinessError) &&
                                error.respond_to?(:details) &&
                                !error.details.empty?

        nil
      end

      # Get custom headers for specific error types
      # @param error [Exception] The error to get headers for
      # @return [Proc, nil] A proc that generates custom headers
      def self.get_custom_headers(error)
        case error
        when Exceptions::NotFoundError
          { 'x-error-type' => 'object-not-found' }
        when Exceptions::TooManyRequestsError
          { 'Retry-After' => error.retry_after.to_s }
        end
      end

      # Check if an error is of a specific type (by class name)
      # @param error [Exception] The error to check
      # @param error_class [Class] The error class to check against
      # @return [Boolean] True if the error is of the specified type
      def self.of_type?(error, error_class)
        # Direct instance check
        return true if error.is_a?(error_class)

        # Check by class name (handles cross-package version mismatches)
        error.class.name.split('::').last == error_class.name.split('::').last
      end

      private_class_method :get_error_status, :get_error_message, :get_error_data,
                           :get_custom_headers, :of_type?
    end
  end
end
