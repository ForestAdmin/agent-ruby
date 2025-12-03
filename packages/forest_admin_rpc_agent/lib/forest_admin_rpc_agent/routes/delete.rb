require 'jsonapi-serializers'

module ForestAdminRpcAgent
  module Routes
    class Delete < BaseRoute
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminAgent::Utils
      include ForestAdminAgent::Routes::QueryHandler

      def initialize
        super('rpc/:collection_name/delete', 'post', 'rpc_delete')
      end

      def handle_request(args)
        return {} unless args[:params]['collection_name']

        datasource = ForestAdminRpcAgent::Facades::Container.datasource
        collection = get_collection_safe(datasource, args[:params]['collection_name'])
        filter = FilterFactory.from_plain_object(args[:params]['filter'])

        collection.delete(args[:caller], filter)
      end
    end
  end
end
