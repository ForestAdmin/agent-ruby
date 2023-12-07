require 'jsonapi-serializers'

module ForestAdminAgent
  module Routes
    module Resources
      module Related
        class CountRelated < AbstractRelatedRoute
          include ForestAdminAgent::Builder
          include ForestAdminDatasourceToolkit::Utils
          include ForestAdminDatasourceToolkit::Components::Query
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
            build(args)
            @permissions.can?(:browse, @collection)

            if @child_collection.is_countable?
              filter = Filter.new(condition_tree: @permissions.get_scope(@collection))
              id = Utils::Id.unpack_id(@collection, args[:params]['id'], with_key: true)
              result = Collection.aggregate_relation(
                @collection,
                id,
                args[:params]['relation_name'],
                @caller,
                filter,
                Aggregation.new(operation: 'Count')
              )

              return {
                name: @child_collection.name,
                content: {
                  count: result[0][:value]
                }
              }
            end

            {
              name: @child_collection.name,
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
