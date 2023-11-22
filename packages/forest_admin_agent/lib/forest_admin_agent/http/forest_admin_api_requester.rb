require 'faraday'

module ForestAdminAgent
  module Http
    class ForestAdminApiRequester
      include ForestAdminDatasourceToolkit::Exceptions

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

      def self.handle_response_error(error)
        raise error if error.is_a?(ForestException)

        if error.message.include?('certificate')
          raise ForestException,
                'ForestAdmin server TLS certificate cannot be verified. Please check that your system time is set properly.'
        end

        if error.code.zero? || error.code == 502
          raise ForestException, 'Failed to reach ForestAdmin server. Are you online?'
        end

        if error.code == 404
          raise ForestException,
                'ForestAdmin server failed to find the project related to the envSecret you configured. Can you check that you copied it properly in the Forest initialization?'
        end

        if error.code == 503
          raise ForestException,
                'Forest is in maintenance for a few minutes. We are upgrading your experience in the forest. We just need a few more minutes to get it right.'
        end

        raise ForestException,
              'An unexpected error occurred while contacting the ForestAdmin server. Please contact support@forestadmin.com for further investigations.'
      end
    end
  end
end
