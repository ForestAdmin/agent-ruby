require 'jsonapi-serializers'

module ForestAdminAgent
  module Routes
    module Resources
      class Store < AbstractAuthenticatedRoute
        include ForestAdminAgent::Builder
        def setup_routes
          add_route('forest_create', 'post', '/:collection_name', ->(args) { handle_request(args) })

          self
        end

        def handle_request(args = {})
          build(args)
          data, = format_attributes(args)
          record = @collection.create(@caller, data)

          {
            name: args[:params]['collection_name'],
            content: JSONAPI::Serializer.serialize(
              record,
              is_collection: false,
              serializer: Serializer::ForestSerializer
            )
          }
        end
      end
    end
  end
end
