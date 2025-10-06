require 'faraday'
require 'openssl'
require 'json'
require 'time'

module ForestAdminDatasourceRpc
  module Utils
    class RpcClient
      # RpcClient handles HTTP communication with the RPC Agent.
      #
      # Error Handling:
      # When the RPC agent returns an error, this client automatically maps HTTP status codes
      # to appropriate Forest Admin exception types. This ensures business errors from the
      # RPC agent are properly propagated to the datasource_rpc.
      #
      # To add support for a new error type:
      # 1. Add the status code and exception class to ERROR_STATUS_MAP
      # 2. (Optional) Add a default message to generate_default_message method
      # 3. Tests will automatically cover the new mapping

      # Map HTTP status codes to Forest Admin exception classes
      ERROR_STATUS_MAP = {
        400 => ForestAdminAgent::Http::Exceptions::ValidationError,
        401 => ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient,
        403 => ForestAdminAgent::Http::Exceptions::ForbiddenError,
        404 => ForestAdminAgent::Http::Exceptions::NotFoundError,
        409 => ForestAdminAgent::Http::Exceptions::ConflictError,
        422 => ForestAdminAgent::Http::Exceptions::UnprocessableError
      }.freeze

      def initialize(api_url, auth_secret)
        @api_url = api_url
        @auth_secret = auth_secret
      end

      def call_rpc(endpoint, method: :get, payload: nil, symbolize_keys: false)
        client = Faraday.new(url: @api_url) do |faraday|
          faraday.request :json
          faraday.response :json, parser_options: { symbolize_names: symbolize_keys }
          faraday.adapter Faraday.default_adapter
          faraday.ssl.verify = !ForestAdminRpcAgent::Facades::Container.cache(:debug)
        end

        timestamp = Time.now.utc.iso8601(3)
        signature = generate_signature(timestamp)

        headers = {
          'Content-Type' => 'application/json',
          'X_TIMESTAMP' => timestamp,
          'X_SIGNATURE' => signature
        }

        response = client.send(method, endpoint, payload, headers)

        handle_response(response)
      end

      private

      def generate_signature(timestamp)
        OpenSSL::HMAC.hexdigest('SHA256', @auth_secret, timestamp)
      end

      def handle_response(response)
        raise_appropriate_error(response) unless response.success?

        response.body
      end

      def raise_appropriate_error(response)
        error_body = parse_error_body(response)
        status = response.status
        url = response.env.url
        message = error_body[:message] || generate_default_message(status, url)

        exception_class = ERROR_STATUS_MAP[status]

        if exception_class
          raise exception_class, message
        elsif status >= 500
          raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                "Server Error: #{message}"
        else
          raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                "RPC request failed: #{status} - #{message}"
        end
      end

      def generate_default_message(status, url)
        default_messages = {
          400 => "Bad Request: #{url}",
          401 => "Unauthorized: #{url}",
          403 => "Forbidden: #{url}",
          404 => "Not Found: #{url}",
          409 => "Conflict: #{url}",
          422 => "Unprocessable Entity: #{url}"
        }

        default_messages[status] || "Unknown error (#{url})"
      end

      def parse_error_body(response)
        body = response.body

        # If body is already a hash (Faraday parsed it as JSON)
        return symbolize_error_keys(body) if body.is_a?(Hash)

        # Try to parse as JSON if it's a string
        if body.is_a?(String) && !body.empty?
          begin
            parsed = JSON.parse(body)
            return symbolize_error_keys(parsed)
          rescue JSON::ParserError
            # If parsing fails, return the body as the message
            return { message: body }
          end
        end

        # Fallback for empty or unexpected body types
        { message: 'Unknown error' }
      end

      def symbolize_error_keys(hash)
        {
          message: hash['error'] || hash['message'] || hash[:error] || hash[:message],
          errors: hash['errors'] || hash[:errors],
          name: hash['name'] || hash[:name]
        }.compact
      end
    end
  end
end
