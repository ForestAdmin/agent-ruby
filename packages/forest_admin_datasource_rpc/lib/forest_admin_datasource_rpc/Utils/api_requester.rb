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
            ssl: { verify: !Facades::Container.cache(:debug) }
          }
        )
      end
    end
  end
end
