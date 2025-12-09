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

      HTTP_NOT_MODIFIED = 304

      # Special return value to indicate schema has not changed (HTTP 304)
      NotModified = Class.new

      def initialize(api_url, auth_secret)
        @api_url = api_url
        @auth_secret = auth_secret
      end

      # rubocop:disable Metrics/ParameterLists
      def call_rpc(endpoint, caller: nil, method: :get, payload: nil, symbolize_keys: false, if_none_match: nil)
        client = Faraday.new(url: @api_url) do |faraday|
          faraday.request :json
          faraday.response :json, parser_options: { symbolize_names: symbolize_keys }
          faraday.adapter Faraday.default_adapter
          faraday.ssl.verify = !ForestAdminAgent::Facades::Container.cache(:debug)
        end

        timestamp = Time.now.utc.iso8601(3)
        signature = generate_signature(timestamp)

        headers = {
          'Content-Type' => 'application/json',
          'X_TIMESTAMP' => timestamp,
          'X_SIGNATURE' => signature
        }

        headers['forest_caller'] = caller.to_json if caller
        headers['If-None-Match'] = %("#{if_none_match}") if if_none_match

        response = client.send(method, endpoint, payload, headers)

        handle_response(response, _symbolize_keys: symbolize_keys)
      end
      # rubocop:enable Metrics/ParameterLists

      private

      def generate_signature(timestamp)
        OpenSSL::HMAC.hexdigest('SHA256', @auth_secret, timestamp)
      end

      # Response wrapper for successful responses that includes headers
      class Response
        attr_reader :body, :etag

        def initialize(body, etag = nil)
          @body = body
          @etag = etag
        end
      end

      def handle_response(response, _symbolize_keys: false)
        # For successful responses, return the body with ETag if present
        if response.success?
          etag = extract_etag(response)
          return Response.new(response.body, etag)
        end

        # Handle 304 Not Modified - schema has not changed (not an error)
        return NotModified if response.status == HTTP_NOT_MODIFIED

        # For other non-success responses, raise appropriate error
        raise_appropriate_error(response)
      end

      def extract_etag(response)
        etag = response.headers['ETag'] || response.headers['etag']
        return nil unless etag

        # Strip quotes from ETag value
        etag.gsub(/\A"?|"?\z/, '')
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
