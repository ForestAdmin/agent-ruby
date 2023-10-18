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

        private

        def format_attributes(args)
          record = args[:params][:data][:attributes].permit(@collection.fields.keys).to_h
          relations = {}

          args[:params][:data][:relationships].to_unsafe_h.map do |field, value|
            schema = @collection.fields[field]

            record[schema.foreign_key] = value[:data][schema.foreign_key_target] if schema.type == 'ManyToOne'
          end

          [record, relations]
        end
      end
    end
  end
end
