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
          id = Utils::Id.unpack_id(@collection, args[:params]['id'], true)
          caller = ForestAdminAgent::Utils::QueryStringParser.parse_caller(args)
          condition_tree = OpenStruct.new(field: 'id' , operator: "EQUAL", value: id['id'])
          #TODO: replace condition_tree by ConditionTreeFactory.matchIds(this.collection.schema, [id]),
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            condition_tree: condition_tree,
            page: ForestAdminAgent::Utils::QueryStringParser.parse_pagination(args)
          )
          projection = ProjectionFactory.all(@collection)

          records = @collection.list(caller, filter, projection)

          raise Http::Exceptions::NotFoundError.new 'Record does not exists' unless records.size > 0

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
