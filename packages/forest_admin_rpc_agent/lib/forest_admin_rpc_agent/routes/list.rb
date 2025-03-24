require 'jsonapi-serializers'

module ForestAdminRpcAgent
  module Routes
    class List < BaseRoute
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminAgent::Utils
      include ForestAdminAgent::Routes::QueryHandler

      def initialize
        super('rpc/:collection_name/list', 'get', 'rpc_list')
      end

      def handle_request(args)
        return '{}' unless args[:params]['collection_name']

        caller = ForestAdminDatasourceToolkit::Components::Caller.new(
          **args[:params]['caller'].to_h.transform_keys(&:to_sym)
        )
        datasource = ForestAdminRpcAgent::Facades::Container.datasource
        collection = datasource.get_collection(args[:params]['collection_name'])
        projection = Projection.new(args[:params]['projection'])
        filter = FilterFactory.from_plain_object(args[:params]['filter'])

        collection.list(caller, filter, projection).to_json
      end
    end
  end
end
