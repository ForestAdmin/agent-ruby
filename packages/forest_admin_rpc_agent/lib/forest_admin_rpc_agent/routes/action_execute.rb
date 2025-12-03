require 'jsonapi-serializers'

module ForestAdminRpcAgent
  module Routes
    class ActionExecute < BaseRoute
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminAgent::Utils
      include ForestAdminAgent::Routes::QueryHandler

      def initialize
        super('rpc/:collection_name/action-execute', 'post', 'rpc_action_execute')
      end

      def handle_request(args)
        return {} unless args[:params]['collection_name']

        datasource = ForestAdminRpcAgent::Facades::Container.datasource
        collection = get_collection_safe(datasource, args[:params]['collection_name'])
        filter = FilterFactory.from_plain_object(args[:params]['filter'])
        data = args[:params]['data']
        action = args[:params]['action']

        collection.execute(args[:caller], action, data, filter)
      end
    end
  end
end
