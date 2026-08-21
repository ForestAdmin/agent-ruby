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
          drop_relationships!(args)
          data = format_attributes(args, context.collection)
          context.collection.update(context.caller, filter, data)
          # The projection is ours, not the caller's, so it is redacted rather than refused: a write
          # must not 403 because the row it wrote carries a relation the caller cannot read.
          projection = context.permissions.redact_projection(
            context.collection,
            ProjectionFactory.all(context.collection),
            named_by_caller: false
          )
          records = context.collection.list(context.caller, filter, projection)

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

        private

        # The frontend writes relations through PUT /:collection/:id/relationships/:name, which fires
        # before this route. Honouring the relationships block here would turn the untouched relations
        # it always resends as `data: null` into foreign keys set to nil. Parity with agent-nodejs.
        def drop_relationships!(args)
          args[:params][:data].delete(:relationships)
        end
      end
    end
  end
end
