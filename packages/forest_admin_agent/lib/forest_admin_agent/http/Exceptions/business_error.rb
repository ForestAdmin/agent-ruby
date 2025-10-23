module ForestAdminAgent
  module Http
    module Exceptions
      # Parent class for all business errors
      # This is the base class that all specific error types inherit from
      class BusinessError < StandardError
        attr_reader :details, :cause

        def initialize(message = nil, details: {}, cause: nil)
          super(message)
          @details = details || {}
          @cause = cause
        end

        # Returns the name of the error class
        def name
          self.class.name.split('::').last
        end
      end

      # ====================
      # Lowest level errors
      # ====================
      # Note: Some error classes (ForbiddenError, NotFoundError, ConflictError, UnprocessableError, ValidationError)
      # are defined in their own files for backward compatibility with HttpException

      class UnavailableForLegalReasonsError < BusinessError
        def initialize(message = 'Unavailable for legal reasons', details: {})
          super
        end
      end

      class BadRequestError < BusinessError
        def initialize(message = 'Bad request', details: {})
          super
        end
      end

      class ContentTooLargeError < BusinessError
        def initialize(message = 'Content too large', details: {})
          super
        end
      end

      class FailedDependencyError < BusinessError
        def initialize(message = 'Failed dependency', details: {})
          super
        end
      end

      class TooEarlyError < BusinessError
        def initialize(message = 'Too early', details: {})
          super
        end
      end

      class InternalServerError < BusinessError
        def initialize(message = 'Internal server error', details: {}, cause: nil)
          super
        end
      end

      class PaymentRequiredError < BusinessError
        def initialize(message = 'Payment required', details: {})
          super
        end
      end

      class BadGatewayError < BusinessError
        def initialize(message = 'Bad gateway error', details: {}, cause: nil)
          super
        end
      end

      class ServiceUnavailableError < BusinessError
        def initialize(message = 'Service unavailable error', details: {}, cause: nil)
          super
        end
      end

      class TooManyRequestsError < BusinessError
        attr_reader :retry_after

        def initialize(message, retry_after, details: {})
          super(message, details: details)
          @retry_after = retry_after
        end
      end

      class UnauthorizedError < BusinessError
        def initialize(message = 'Unauthorized', details: {})
          super
        end
      end

      class ValidationFailedError < BadRequestError
        def initialize(message = 'Validation failed', details: {})
          super
        end
      end

      class NotFoundError < BusinessError
        def initialize(message, details: {})
          super
        end
      end
    end
  end
end
