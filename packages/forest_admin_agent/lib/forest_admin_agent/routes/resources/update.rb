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
          id = Utils::Id.unpack_id(@collection, args[:params]['id'], with_key: true)
          caller = ForestAdminAgent::Utils::QueryStringParser.parse_caller(args)
          condition_tree = ConditionTree::ConditionTreeFactory.match_records(@collection, [id])
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            condition_tree: condition_tree,
            page: ForestAdminAgent::Utils::QueryStringParser.parse_pagination(args)
          )
          data = format_attributes(args)
          @collection.update(@caller, filter, data)
          records = @collection.list(caller, filter, ProjectionFactory.all(@collection))

          {
            name: args[:params]['collection_name'],
            content: JSONAPI::Serializer.serialize(
              records[0],
              is_collection: false,
              serializer: Serializer::ForestSerializer
            )
          }
        end
      end
    end
  end
end
