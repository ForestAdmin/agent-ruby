require 'jsonapi-serializers'
require 'ostruct'

module ForestAdminAgent
  module Routes
    module Resources
      class Update < AbstractAuthenticatedRoute
        include ForestAdminAgent::Builder
        include ForestAdminDatasourceToolkit::Components::Query

        def setup_routes
          add_route('forest_update', 'put', '/:collection_name/:id', ->(args) { handle_request(args) })

          self
        end

        def handle_request(args = {})
          build(args)
          @permissions.can?(:edit, @collection)
          scope = @permissions.get_scope(@collection)
          id = Utils::Id.unpack_id(@collection, args[:params]['id'], with_key: true)
          condition_tree = ConditionTree::ConditionTreeFactory.match_records(@collection, [id])
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            condition_tree: ConditionTree::ConditionTreeFactory.intersect([condition_tree, scope])
          )
          data = format_attributes(args)
          @collection.update(@caller, filter, data)
          records = @collection.list(@caller, filter, ProjectionFactory.all(@collection))

          {
            name: args[:params]['collection_name'],
            content: JSONAPI::Serializer.serialize(
              records[0],
              is_collection: false,
              class_name: @collection.name,
              serializer: Serializer::ForestSerializer
            )
          }
        end
      end
    end
  end
end
