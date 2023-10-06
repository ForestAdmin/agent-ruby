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
          { name: args['collection_name'], content: args['collection_name'] }
        end
      end
    end
  end
end
