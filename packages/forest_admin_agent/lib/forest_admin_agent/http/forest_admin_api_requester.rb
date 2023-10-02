require 'faraday'

module ForestAdminAgent
  module Http
    class ForestAdminApiRequester
      def initialize
        @headers = {
          'Content-Type' => 'application/json',
          'forest-secret-key' => Facades::Container.cache(:env_secret)
        }
        @client = Faraday.new(
          Facades::Container.cache(:forest_server_url),
          {
            headers: @headers
          }
        )
      end

      def get(url, params)
        @client.get(url, params.to_json)
      end

      def post(url, params)
        @client.post(url, params.to_json)
      end
    end
  end
end
