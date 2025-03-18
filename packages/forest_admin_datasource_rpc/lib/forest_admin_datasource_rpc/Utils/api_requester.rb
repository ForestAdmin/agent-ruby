require 'faraday'

module ForestAdminDatasourceRpc
  module Utils
    class ApiRequester
      include ForestAdminDatasourceToolkit::Exceptions

      def initialize(url, token)
        @headers = {
          'Content-Type' => 'application/json',
          'Authorization' => token
        }
        @client = Faraday.new(
          url,
          {
            headers: @headers,
            ssl: { verify: !ForestAdminRpcAgent::Facades::Container.cache(:debug) }
          }
        )
      end

      def get(url, params = {})
        @client.get(url, params)
      end

      def post(url, params = {})
        @client.post(url, params)
      end

      def put(url, params = {})
        @client.put(url, params)
      end

      def delete(url, params = {})
        @client.delete(url, params)
      end
    end
  end
end
