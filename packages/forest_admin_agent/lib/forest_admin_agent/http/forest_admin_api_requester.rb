require 'faraday'

module ForestAdminAgent
  module Http
    class ForestAdminApiRequester
      include ForestAdminAgent::Http::Exceptions
      include ForestAdminDatasourceToolkit::Exceptions

      def initialize
        @headers = {
          'Content-Type' => 'application/json',
          'forest-secret-key' => Facades::Container.cache(:env_secret)
        }
        @client = Faraday.new(
          Facades::Container.cache(:forest_server_url),
          {
            headers: @headers,
            ssl: { verify: !Facades::Container.cache(:debug) }
          }
        )
      end

      def get(url, params = nil)
        @client.get(url, params)
      end

      def post(url, params = nil)
        @client.post(url, params)
      end

      def handle_response_error(error)
        # Re-raise if it's already a BusinessError
        raise error if error.is_a?(ForestAdminAgent::Http::Exceptions::BusinessError)
        raise error if error.is_a?(ForestException)

        if error.response[:message]&.include?('certificate')
          raise InternalServerError.new(
            'ForestAdmin server TLS certificate cannot be verified. Please check that your system time is set properly.',
            details: { error: error.message },
            cause: error
          )
        end

        raise_for_status(error.response[:status], cause: error)
      end

      # Faraday does not raise on HTTP error statuses here (no raise_error middleware
      # configured), so a response has to be checked explicitly to turn e.g. an
      # invalid envSecret (404) into the same typed errors as handle_response_error.
      def raise_for_response!(response)
        return if response.success?

        raise_for_status(response.status)
      end

      private

      def raise_for_status(status, cause: nil)
        if status.zero? || status == 502
          raise BadGatewayError.new(
            'Failed to reach ForestAdmin server. Are you online?',
            details: { status: status },
            cause: cause
          )
        end

        if status == 404
          raise NotFoundError.new(
            'ForestAdmin server failed to find the project related to the envSecret you configured. Can you check that you copied it properly in the Forest initialization?',
            details: { status: status }
          )
        end

        if status == 503
          raise ServiceUnavailableError.new(
            'Forest is in maintenance for a few minutes. We are upgrading your experience in the forest. We just need a few more minutes to get it right.',
            details: { status: status },
            cause: cause
          )
        end

        raise InternalServerError.new(
          'An unexpected error occurred while contacting the ForestAdmin server. Please contact support@forestadmin.com for further investigations.',
          details: { status: status },
          cause: cause
        )
      end
    end
  end
end
