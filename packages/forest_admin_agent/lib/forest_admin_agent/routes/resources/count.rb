require 'jsonapi-serializers'

module ForestAdminAgent
  module Routes
    module Resources
      class Count < AbstractAuthenticatedRoute
        include ForestAdminAgent::Builder
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
        include ForestAdminAgent::Routes::QueryHandler

        def setup_routes
          add_route('forest_count', 'get', '/:collection_name/count', ->(args) { handle_request(args) })

          self
        end

        def handle_request(args = {})
          context = build(args)
          context.permissions.can?(:browse, context.collection)

          if context.collection.is_countable?
            filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
              condition_tree: ConditionTreeFactory.intersect(
                [
                  context.permissions.get_scope(context.collection),
                  parse_query_segment(context.collection, args, context.permissions, context.caller),
                  ForestAdminAgent::Utils::QueryStringParser.parse_condition_tree(context.collection, args)
                ]
              ),
              search: QueryStringParser.parse_search(context.collection, args),
              search_extended: QueryStringParser.parse_search_extended(args),
              segment: QueryStringParser.parse_segment(context.collection, args)
            )
            aggregation = ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(operation: 'Count')
            result = context.collection.aggregate(context.caller, filter, aggregation)

            return {
              name: args[:params]['collection_name'],
              content: {
                count: result.empty? ? 0 : result[0]['value']
              }
            }
          end

          {
            name: args[:params]['collection_name'],
            content: {
              count: 'deactivated'
            }
          }
        end
      end
    end
  end
end
