require 'json'
module ForestAdminAgent
  module Routes
    module Capabilities
      class Collections < AbstractRoute
        include ForestAdminDatasourceToolkit::Schema

        def setup_routes
          add_route('forest_capabilities_collections', 'post', '/capabilities', ->(args) { handle_request(args) })

          self
        end

        def handle_request(args = {})
          @datasource = ForestAdminAgent::Facades::Container.datasource
          collections = args[:params]['collectionNames'] || @datasource.collections.keys

          result = collections.map do |collection_name|
            collection = @datasource.get_collection(collection_name)
            {
              name: collection.name,
              fields: collection.schema[:fields].select { |_, field| field.is_a?(ColumnSchema) }.map do |name, field|
                {
                  name: name,
                  type: field.column_type,
                  operators: field.filter_operators.map { |operator| operator }
                }
              end
            }
          end

          {
            content: {
              collections: result
            },
            status: 200
          }
        end
      end
    end
  end
end
