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
          build(args)
          @permissions.can?(:browse, @collection)

          if @collection.is_countable?
            filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
              condition_tree: ConditionTreeFactory.intersect(
                [
                  @permissions.get_scope(@collection),
                  parse_query_segment(@collection, args, @permissions, @caller),
                  ForestAdminAgent::Utils::QueryStringParser.parse_condition_tree(@collection, args)
                ]
              ),
              search: QueryStringParser.parse_search(@collection, args),
              search_extended: QueryStringParser.parse_search_extended(args),
              segment: QueryStringParser.parse_segment(@collection, args)
            )
            aggregation = ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(operation: 'Count')
            result = @collection.aggregate(@caller, filter, aggregation)

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
