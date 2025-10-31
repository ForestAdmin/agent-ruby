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
        datasource = agent.customizer.datasource(ForestAdminRpcAgent::Facades::Container.logger)

        schema[:collections] = datasource.collections
                                         .map { |_name, collection| collection.schema.merge({ name: collection.name }) }
                                         .sort_by { |collection| collection[:name] }

        connections = []
        agent.customizer.datasources.each do |root_datasource|
          connections = connections.union(
            root_datasource.live_query_connections.keys.map { |connection_name| { name: connection_name } }
          )
        end
        schema[:native_query_connections] = connections

        schema.to_json
      end
    end
  end
end
