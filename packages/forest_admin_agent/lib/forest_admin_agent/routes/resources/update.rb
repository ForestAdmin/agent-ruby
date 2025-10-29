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
          context = build(args)
          context.permissions.can?(:edit, context.collection)
          scope = context.permissions.get_scope(context.collection)
          primary_key_values = Utils::Id.unpack_id(context.collection, args[:params]['id'], with_key: true)
          condition_tree = ConditionTree::ConditionTreeFactory.match_records(context.collection, [primary_key_values])
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            condition_tree: ConditionTree::ConditionTreeFactory.intersect([condition_tree, scope])
          )
          data = format_attributes(args, context.collection)
          context.collection.update(context.caller, filter, data)
          records = context.collection.list(context.caller, filter, ProjectionFactory.all(context.collection))

          {
            name: args[:params]['collection_name'],
            content: JSONAPI::Serializer.serialize(
              records[0],
              is_collection: false,
              class_name: context.collection.name,
              serializer: Serializer::ForestSerializer
            )
          }
        end
      end
    end
  end
end
