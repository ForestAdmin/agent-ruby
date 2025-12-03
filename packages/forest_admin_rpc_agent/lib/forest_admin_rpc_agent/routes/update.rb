require 'jsonapi-serializers'

module ForestAdminRpcAgent
  module Routes
    class Update < BaseRoute
      include ForestAdminDatasourceToolkit::Components::Query

      def initialize
        super('rpc/:collection_name/update', 'post', 'rpc_update')
      end

      def handle_request(args)
        return {} unless args[:params]['collection_name']

        datasource = ForestAdminRpcAgent::Facades::Container.datasource
        collection = get_collection_safe(datasource, args[:params]['collection_name'])
        filter = FilterFactory.from_plain_object(args[:params]['filter'])

        collection.update(args[:caller], filter, args[:params]['patch'])
      end
    end
  end
end
