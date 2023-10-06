module ForestAdminAgent
  module Routes
    module Resources
      class List < AbstractAuthenticatedRoute
        include ForestAdminAgent::Builder
        def setup_routes
          add_route('forest_list', 'get', '/:collection_name', ->(args) { handle_request(args) })

          self
        end

        def handle_request(args = {})
          # is_collection true for a list false for a single record
          # JSONAPI::Serializer.serialize(record, is_collection: true, serializer: Serializer::ForestSerializer)
          build(args)
          caller = ForestAdminAgent::Utils::QueryStringParser.parse_caller(args)
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            page: ForestAdminAgent::Utils::QueryStringParser.parse_pagination(args)
          )
          projection = ForestAdminAgent::Utils::QueryStringParser.parse_projection_with_pks(@collection, args)
          records = @collection.list(caller, filter, projection)

          { name: args[:params]['collection_name'], content: args[:params]['collection_name'] }
        end
      end
    end
  end
end
