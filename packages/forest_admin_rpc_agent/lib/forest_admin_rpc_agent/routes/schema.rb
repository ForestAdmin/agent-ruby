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
        rpc_collections = agent.rpc_collections
        schema = agent.customizer.schema
        schema[:collections] ||= []
        schema[:rpc_relations] ||= {}
        collections = agent.customizer.datasource(ForestAdminRpcAgent::Facades::Container.logger).collections

        # schema[:collections] = collections
        #                             .map { |_name, collection| collection.schema.merge({ name: collection.name }) }
        #                             .sort_by { |collection| collection[:name] }

        collections.each_value do |collection|
          if rpc_collections.include?(collection.name)
            relations = collection.schema[:fields].each_with_object({}) do |(name, field), hash|
              if field.is_a?(ForestAdminDatasourceToolkit::Schema::RelationSchema) &&
                 !rpc_collections.include?(field[:foreign_collection])
                hash[name] = field
              end
            end

            schema[:rpc_relations][collection.name] = relations unless relations.empty?
          else
            schema[:collections] << collection.schema.merge({ name: collection.name })
          end
        end

        schema[:collections].sort_by! { |collection| collection[:name] }

        schema.to_json
      end
    end
  end
end
