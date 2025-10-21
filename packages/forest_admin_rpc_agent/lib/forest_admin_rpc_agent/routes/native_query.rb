require 'jsonapi-serializers'

module ForestAdminRpcAgent
  module Routes
    class NativeQuery < BaseRoute
      def initialize
        super('rpc-native-query', 'post', 'rpc_native_query')
      end

      def handle_request(args)
        return '{}' unless args[:params]['connection_name'] && args[:params]['query']

        connection_name = args[:params]['connection_name']
        query = args[:params]['query']
        binds = args[:params]['binds'] || []
        datasource = ForestAdminRpcAgent::Facades::Container.datasource

        datasource.execute_native_query(connection_name, query, binds).to_json
      end
    end
  end
end
