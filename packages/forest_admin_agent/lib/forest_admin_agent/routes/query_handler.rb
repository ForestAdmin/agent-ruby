module ForestAdminAgent
  module Routes
    module QueryHandler
      include ForestAdminAgent::Utils
      include ForestAdminAgent::Builder
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Validations

      def inject_context_variables(datasource, connection_name, query, permissions, caller, context_variables)
        user = permissions.get_user_data(caller.id)
        team = permissions.get_team(caller.rendering_id)
        context_variables = ContextVariables.new(team, user, context_variables)

        ContextVariablesInjector.inject_context_in_native_query(datasource, connection_name, query, context_variables)
      end

      def execute_query(datasource, query, connection_name, permissions, caller, context_variables)
        query = query.strip
        query, binds = inject_context_variables(datasource, connection_name, query, permissions, caller,
                                                context_variables)

        datasource.execute_native_query(connection_name, query, binds)
      end

      def parse_query_segment(collection, args, permissions, caller)
        segment_query = QueryStringParser.subset_or_query(args, :segmentQuery)
        return unless segment_query

        connection_name = QueryStringParser.subset_or_query(args, :connectionName)
        unless connection_name
          raise ForestAdminAgent::Http::Exceptions::UnprocessableError, 'Missing native query connection attribute'
        end

        QueryValidator.valid?(segment_query)

        permissions.can_execute_query_segment?(collection, segment_query, connection_name)

        ids = execute_query(
          collection.datasource,
          segment_query,
          connection_name,
          permissions,
          caller,
          QueryStringParser.subset_or_query(args, :contextVariables)
        ).map(&:values)

        condition_tree_segment = ConditionTree::ConditionTreeFactory.match_ids(collection, ids)
        ConditionTreeValidator.validate(condition_tree_segment, collection)

        condition_tree_segment
      end

      def build_context_filter(collection, args, permissions, caller)
        search = QueryStringParser.parse_search(collection, args)

        Filter.new(
          condition_tree: ConditionTree::ConditionTreeFactory.intersect(
            [
              permissions.get_scope(collection),
              QueryStringParser.parse_condition_tree(collection, args),
              parse_query_segment(collection, args, permissions, caller)
            ]
          ),
          search: search,
          search_extended: search && QueryStringParser.parse_search_extended(args),
          segment: QueryStringParser.parse_segment(collection, args)
        )
      end
    end
  end
end
