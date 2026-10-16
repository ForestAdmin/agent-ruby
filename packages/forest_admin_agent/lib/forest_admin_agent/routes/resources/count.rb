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
            filter = build_context_filter(context.collection, args, context.permissions, context.caller)
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
