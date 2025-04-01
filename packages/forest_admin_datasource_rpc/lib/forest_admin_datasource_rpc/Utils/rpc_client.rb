require 'faraday'
require 'openssl'
require 'json'
require 'time'

module ForestAdminDatasourceRpc
  module Utils
    class RpcClient
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

        timestamp = Time.now.utc.iso8601
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
        unless response.success?
          raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                "RPC request failed: #{response.status} for uri #{response.env.url}"
        end

        response.body
      end
    end
  end
end
