require 'jsonapi-serializers'

module ForestAdminRpcAgent
  module Routes
    class List < BaseRoute
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminAgent::Utils
      include ForestAdminAgent::Routes::QueryHandler

      def initialize
        super('rpc/:collection_name/list', 'post', 'rpc_list')
      end

      def handle_request(args)
        return '{}' unless args[:params]['collection_name']

        datasource = ForestAdminRpcAgent::Facades::Container.datasource
        collection = datasource.get_collection(args[:params]['collection_name'])
        projection = Projection.new(args[:params]['projection'])
        filter = FilterFactory.from_plain_object(args[:params]['filter'])

        collection.list(args[:caller], filter, projection).to_json
      end
    end
  end
end
