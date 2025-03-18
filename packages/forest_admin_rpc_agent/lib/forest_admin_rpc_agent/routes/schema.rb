module ForestAdminRpcAgent
  module Routes
    class Schema < BaseRoute
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminAgent::Utils
      include ForestAdminAgent::Routes::QueryHandler

      def initialize
        super('rpc-schema', 'get', 'rpc_schema')
      end

      def handle_request(_params)
        agent = ForestAdminRpcAgent::Agent.instance
        schema = agent.customizer.schema
        schema[:collections] = agent.customizer.datasource(ForestAdminRpcAgent::Facades::Container.logger)
                                    .collections
                                    .map { |_name, collection| collection.schema.merge({ name: collection.name }) }
                                    .sort_by { |collection| collection[:name] }

        schema.to_json
      end
    end
  end
end
