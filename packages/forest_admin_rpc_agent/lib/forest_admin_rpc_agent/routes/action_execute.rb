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
        return '{}' unless args[:params]['collection_name']

        datasource = ForestAdminRpcAgent::Facades::Container.datasource
        collection = datasource.get_collection(args[:params]['collection_name'])

        caller = ForestAdminDatasourceToolkit::Components::Caller.new(
          **args[:params]['caller'].to_h.transform_keys(&:to_sym)
        )
        filter = FilterFactory.from_plain_object(args[:params]['filter'])
        data = args[:params]['data']
        action = args[:params]['action']

        collection.execute(caller, action, data, filter).to_json
      end
    end
  end
end
