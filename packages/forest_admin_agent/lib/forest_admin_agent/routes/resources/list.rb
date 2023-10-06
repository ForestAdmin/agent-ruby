module ForestAdminAgent
  module Routes
    module Resources
      class List < AbstractRoute
        include ForestAdminAgent::Builder
        def setup_routes
          add_route('forest_list', 'get', '/:collection_name', ->(args) { handle_request(args) })

          self
        end

        def handle_request(args = {})
          # is_collection true for a list false for a single record
          # JSONAPI::Serializer.serialize(record, is_collection: true, serializer: Serializer::ForestSerializer)
        end
      end
    end
  end
end
