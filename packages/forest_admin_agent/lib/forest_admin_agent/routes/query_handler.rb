module ForestAdminAgent
  module Routes
    module QueryHandler
      include ForestAdminAgent::Utils
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Validations

      def inject_context_variables(query, permissions, caller, context_variables)
        user = permissions.get_user_data(caller.id)
        team = permissions.get_team(caller.rendering_id)
        context_variables = ContextVariables.new(team, user, context_variables)

        ContextVariablesInjector.inject_context_in_native_query(query, context_variables)
      end

      def execute_query(query, connection_name, permissions, caller, context_variables)
        query = query.strip
        query, context_variables = inject_context_variables(query, permissions, caller, context_variables)

        root_datasource = ForestAdminAgent::Builder::AgentFactory.instance
                                                                 .customizer
                                                                 .get_root_datasource_by_connection(
                                                                   connection_name
                                                                 )
        root_datasource.execute_native_query(
          connection_name,
          query,
          context_variables.values
        )
      end

      def parse_query_segment(collection, args, permissions, caller)
        return unless args[:params][:segmentQuery]

        unless args[:params][:connectionName]
          raise ForestAdminAgent::Http::Exceptions::UnprocessableError, "'connectionName' parameter is mandatory"
        end

        QueryValidator.valid?(args[:params][:segmentQuery])

        permissions.can_execute_query_segment?(collection, args[:params][:segmentQuery], args[:params][:connectionName])

        ids = execute_query(
          args[:params][:segmentQuery],
          args[:params][:connectionName],
          permissions,
          caller,
          args[:params][:contextVariables]
        ).map(&:values)

        condition_tree_segment = ConditionTree::ConditionTreeFactory.match_ids(collection, ids)
        ConditionTreeValidator.validate(condition_tree_segment, collection)

        condition_tree_segment
      end
    end
  end
end
