require 'jwt'
require 'active_support'
require 'active_support/time'

module ForestAdminAgent
  module Utils
    class CallerParser
      include ForestAdminDatasourceToolkit::Exceptions

      def initialize(args)
        @args = args
        @token_data = {}
      end

      def parse
        validate_headers
        @token_data = decode_token
        @token_data[:timezone] = extract_timezone
        @token_data[:request] = { ip: @args[:headers]['action_dispatch.remote_ip'].to_s }
        project, environment = extract_forest_context
        @token_data[:project] = project
        @token_data[:environment] = environment

        ForestAdminDatasourceToolkit::Components::Caller.new(**@token_data.transform_keys(&:to_sym))
      end

      private

      def validate_headers
        return if @args.dig(:headers, 'HTTP_AUTHORIZATION')

        raise Http::Exceptions::HttpException.new(
          401,
          'You must be logged in to access at this resource.'
        )
      end

      def extract_timezone
        timezone = @args[:params]['timezone']
        raise ForestException, 'Missing timezone' unless timezone
        raise ForestException, "Invalid timezone: #{timezone}" unless Time.find_zone(timezone)

        timezone
      end

      def decode_token
        token = @args[:headers]['HTTP_AUTHORIZATION'].split[1]
        JWT.decode(
          token,
          Facades::Container.cache(:auth_secret),
          true,
          { algorithm: 'HS256' }
        )[0].tap { |data| data.delete('exp') }
      end

      def extract_forest_context
        match_data = %r{https://[^/]*/([^/]*)/([^/]*)/([^/]*)}.match(@args[:headers]['HTTP_FOREST_CONTEXT_URL'])
        return [nil, nil] unless match_data

        project = match_data[1]
        environment = match_data[2]
        [project, environment]
      rescue StandardError
        [nil, nil]
      end
    end
  end
end
