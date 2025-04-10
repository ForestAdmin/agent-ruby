require 'jsonapi-serializers'

module ForestAdminRpcAgent
  module Routes
    class Update < BaseRoute
      include ForestAdminDatasourceToolkit::Components::Query

      def initialize
        super('rpc/:collection_name/update', 'post', 'rpc_update')
      end

      def handle_request(args)
        return '{}' unless args[:params]['collection_name']

        caller = ForestAdminDatasourceToolkit::Components::Caller.new(
          **args[:params]['caller'].to_h.transform_keys(&:to_sym)
        )
        datasource = ForestAdminRpcAgent::Facades::Container.datasource
        collection = datasource.get_collection(args[:params]['collection_name'])
        filter = FilterFactory.from_plain_object(args[:params]['filter'])

        collection.update(caller, filter, args[:params]['data']).to_json
      end
    end
  end
end
