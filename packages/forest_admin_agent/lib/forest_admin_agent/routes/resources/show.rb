require 'jsonapi-serializers'
require 'ostruct'

module ForestAdminAgent
  module Routes
    module Resources
      class Show < AbstractAuthenticatedRoute
        include ForestAdminAgent::Builder
        include ForestAdminDatasourceToolkit::Components::Query
        def setup_routes
          add_route('forest_show', 'get', '/:collection_name/:id', ->(args) { handle_request(args) })

          self
        end

        def handle_request(args = {})
          context = build(args)
          context.permissions.can?(:read, context.collection)
          scope = context.permissions.get_scope(context.collection)
          primary_key_values = Utils::Id.unpack_id(context.collection, args[:params]['id'], with_key: true)
          condition_tree = ConditionTree::ConditionTreeFactory.match_records(context.collection, [primary_key_values])
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            condition_tree: ConditionTree::ConditionTreeFactory.intersect([condition_tree, scope])
          )

          projection = ProjectionFactory.all(context.collection, context.datasource)

          records = context.collection.list(context.caller, filter, projection)

          raise Http::Exceptions::NotFoundError, 'Record does not exists' unless records.size.positive?

          {
            name: args[:params]['collection_name'],
            content: JSONAPI::Serializer.serialize(
              records[0],
              class_name: context.collection.name,
              is_collection: false,
              serializer: Serializer::ForestSerializer,
              include: projection.relations(only_keys: true)
            )
          }
        end
      end
    end
  end
end
