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
          build(args)
          @permissions.can?(:read, @collection)
          scope = @permissions.get_scope(@collection)
          id = Utils::Id.unpack_id(@collection, args[:params]['id'], with_key: true)
          condition_tree = ConditionTree::ConditionTreeFactory.match_records(@collection, [id])
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            condition_tree: ConditionTree::ConditionTreeFactory.intersect([condition_tree, scope]),
            page: ForestAdminAgent::Utils::QueryStringParser.parse_pagination(args)
          )

          projection = ProjectionFactory.all(@collection)

          records = @collection.list(@caller, filter, projection)

          raise Http::Exceptions::NotFoundError, 'Record does not exists' unless records.size.positive?

          {
            name: args[:params]['collection_name'],
            content: JSONAPI::Serializer.serialize(
              records[0],
              is_collection: false,
              serializer: Serializer::ForestSerializer,
              include: projection.relations.keys
            )
          }
        end
      end
    end
  end
end
