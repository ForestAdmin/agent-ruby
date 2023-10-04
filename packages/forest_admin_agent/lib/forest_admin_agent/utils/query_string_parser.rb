require 'jwt'

module ForestAdminAgent
  module Utils
    class QueryStringParser
      include ForestAdminDatasourceToolkit::Exceptions
      def self.parse_caller(args)
        unless args[:headers]['HTTP_AUTHORIZATION']
          raise ForestException 'You must be logged in to access at this resource.'
        end

        timezone = args[:params]['timezone']
        raise ForestException 'You must be logged in to access at this resource.' unless timezone

        # if (! in_array($timezone, \DateTimeZone::listIdentifiers(), true)) {
        #   throw new ForestException("Invalid timezone: $timezone");
        # }
        token = args[:headers]['HTTP_AUTHORIZATION'].split[1]
        token_data = JWT.decode(
          token,
          Facades::Container.cache(:auth_secret),
          true,
          { algorithm: 'HS256' }
        )[0]
        token_data.delete('exp')
        token_data[:timezone] = timezone

        ForestAdminDatasourceToolkit::Components::Caller.new(**token_data.transform_keys(&:to_sym))
      end
    end
  end
end
