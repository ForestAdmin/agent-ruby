require 'json'
module ForestAdminAgent
  module Routes
    module Capabilities
      class Collections < AbstractRoute
        include ForestAdminDatasourceToolkit::Schema

        def setup_routes
          add_route('forest_capabilities_collections',
                    'post',
                    '/_internal/capabilities',
                    ->(args) { handle_request(args) })

          self
        end

        def handle_request(args = {})
          datasource = ForestAdminAgent::Facades::Container.datasource
          collections = args[:params]['collectionNames'] || []

          connections = datasource.live_query_connections.keys.map { |connection_name| { name: connection_name } }

          result = collections.map do |collection_name|
            collection = datasource.get_collection(collection_name)
            {
              name: collection.name,
              fields: collection.schema[:fields].select { |_, field| field.is_a?(ColumnSchema) }.map do |name, field|
                {
                  name: name,
                  type: field.column_type,
                  operators: ForestAdminAgent::Utils::Schema::FrontendFilterable.sort_operators(field.filter_operators)
                }
              end
            }
          end

          {
            content: {
              collections: result,
              nativeQueryConnections: connections
            },
            status: 200
          }
        end
      end
    end
  end
end
