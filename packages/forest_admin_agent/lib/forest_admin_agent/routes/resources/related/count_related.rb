require 'jsonapi-serializers'

module ForestAdminAgent
  module Routes
    module Resources
      module Related
        class CountRelated < AbstractRelatedRoute
          include ForestAdminAgent::Builder
          include ForestAdminDatasourceToolkit::Utils
          include ForestAdminDatasourceToolkit::Components::Query
          include ForestAdminAgent::Routes::QueryHandler

          def setup_routes
            add_route(
              'forest_related_count',
              'get',
              '/:collection_name/:id/relationships/:relation_name/count',
              ->(args) { handle_request(args) }
            )

            self
          end

          def handle_request(args = {})
            context = build(args)
            context.permissions.can?(:browse, context.child_collection)

            if context.child_collection.is_countable?
              filter = build_context_filter(context.child_collection, args, context.permissions, context.caller)
              primary_key_values = Utils::Id.unpack_id(context.collection, args[:params]['id'], with_key: true)
              result = Collection.aggregate_relation(
                context.collection,
                primary_key_values,
                args[:params]['relation_name'],
                context.caller,
                filter,
                Aggregation.new(operation: 'Count')
              )

              return {
                name: context.child_collection.name,
                content: {
                  count: result.empty? ? 0 : result[0]['value']
                }
              }
            end

            {
              name: context.child_collection.name,
              content: {
                count: 'deactivated'
              }
            }
          end
        end
      end
    end
  end
end
