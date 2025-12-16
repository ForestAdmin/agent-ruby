require 'faraday'
require 'openssl'
require 'json'
require 'time'

module ForestAdminDatasourceRpc
  module Utils
    # Response wrapper for schema requests that need ETag
    class SchemaResponse
      attr_reader :body, :etag

      def initialize(body, etag = nil)
        @body = body
        @etag = etag
      end
    end

    class RpcClient
      ERROR_STATUS_MAP = {
        400 => ForestAdminAgent::Http::Exceptions::ValidationError,
        401 => ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient,
        403 => ForestAdminAgent::Http::Exceptions::ForbiddenError,
        404 => ForestAdminAgent::Http::Exceptions::NotFoundError,
        409 => ForestAdminAgent::Http::Exceptions::ConflictError,
        422 => ForestAdminAgent::Http::Exceptions::UnprocessableError
      }.freeze

      DEFAULT_ERROR_MESSAGES = {
        400 => 'Bad Request', 401 => 'Unauthorized', 403 => 'Forbidden',
        404 => 'Not Found', 409 => 'Conflict', 422 => 'Unprocessable Entity'
      }.freeze

      HTTP_NOT_MODIFIED = 304
      NotModified = Class.new

      def initialize(api_url, auth_secret)
        @api_url = api_url
        @auth_secret = auth_secret
      end

      # rubocop:disable Metrics/ParameterLists
      def call_rpc(endpoint, caller: nil, method: :get, payload: nil, symbolize_keys: false, if_none_match: nil)
        response = make_request(endpoint, caller: caller, method: method, payload: payload,
                                          symbolize_keys: symbolize_keys, if_none_match: if_none_match)
        handle_response(response)
      end

      # rubocop:enable Metrics/ParameterLists

      def fetch_schema(endpoint, if_none_match: nil)
        response = make_request(endpoint, method: :get, symbolize_keys: true, if_none_match: if_none_match)
        handle_response_with_etag(response)
      end

      private

      DEFAULT_TIMEOUT = 30 # seconds
      DEFAULT_OPEN_TIMEOUT = 10 # seconds

      # rubocop:disable Metrics/ParameterLists
      def make_request(endpoint, caller: nil, method: :get, payload: nil, symbolize_keys: false, if_none_match: nil)
        log_request_start(method, endpoint, if_none_match)

        client = Faraday.new(url: @api_url) do |faraday|
          faraday.request :json
          faraday.response :json, parser_options: { symbolize_names: symbolize_keys }
          faraday.adapter Faraday.default_adapter
          faraday.ssl.verify = !ForestAdminAgent::Facades::Container.cache(:debug)
          faraday.options.timeout = DEFAULT_TIMEOUT
          faraday.options.open_timeout = DEFAULT_OPEN_TIMEOUT
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
        log_request_complete(response, endpoint)
        response
      end
      # rubocop:enable Metrics/ParameterLists

      def generate_signature(timestamp)
        OpenSSL::HMAC.hexdigest('SHA256', @auth_secret, timestamp)
      end

      def handle_response(response)
        return response.body if response.success?
        return NotModified if response.status == HTTP_NOT_MODIFIED

        raise_appropriate_error(response)
      end

      def handle_response_with_etag(response)
        if response.success?
          etag = extract_etag(response)
          ForestAdminAgent::Facades::Container.logger&.log(
            'Debug',
            "[RPC Client] Schema response received (status: #{response.status}, ETag: #{etag || "none"})"
          )
          return SchemaResponse.new(response.body, etag)
        end
        return NotModified if response.status == HTTP_NOT_MODIFIED

        raise_appropriate_error(response)
      end

      def extract_etag(response)
        etag = response.headers['ETag'] || response.headers['etag']
        etag&.gsub(/\A"?|"?\z/, '')
      end

      def raise_appropriate_error(response)
        error_body = parse_error_body(response)
        status = response.status
        url = response.env.url
        message = error_body[:message] || generate_default_message(status, url)

        ForestAdminAgent::Facades::Container.logger&.log(
          'Error',
          "[RPC Client] Request failed (status: #{status}, URL: #{url}, message: #{message})"
        )

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
        prefix = DEFAULT_ERROR_MESSAGES[status] || 'Unknown error'
        "#{prefix}: #{url}"
      end

      def parse_error_body(response)
        body = response.body
        return symbolize_error_keys(body) if body.is_a?(Hash)
        return { message: 'Unknown error' } unless body.is_a?(String) && !body.empty?

        symbolize_error_keys(JSON.parse(body))
      rescue JSON::ParserError
        { message: body }
      end

      def symbolize_error_keys(hash)
        {
          message: hash['error'] || hash['message'] || hash[:error] || hash[:message],
          errors: hash['errors'] || hash[:errors],
          name: hash['name'] || hash[:name]
        }.compact
      end

      def log_request_start(method, endpoint, if_none_match)
        etag_info = if_none_match ? " (If-None-Match: #{if_none_match})" : ''
        ForestAdminAgent::Facades::Container.logger&.log(
          'Debug',
          "[RPC Client] Sending #{method.to_s.upcase} request to #{@api_url}#{endpoint}#{etag_info}"
        )
      end

      def log_request_complete(response, endpoint)
        ForestAdminAgent::Facades::Container.logger&.log(
          'Debug',
          "[RPC Client] Response received (status: #{response.status}, endpoint: #{endpoint})"
        )
      end
    end
  end
end
