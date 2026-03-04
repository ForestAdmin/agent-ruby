require 'json'
module ForestAdminAgent
  module Routes
    module Capabilities
      class Collections < AbstractRoute
        include ForestAdminDatasourceToolkit::Schema
        include ForestAdminDatasourceToolkit::Schema::Relations

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
            aggregation_capabilities = collection.schema[:aggregation_capabilities]

            fields = collection.schema[:fields].filter_map do |name, field|
              if field.is_a?(ManyToOneSchema)
                foreign_key_field = collection.schema[:fields][field.foreign_key]
                {
                  name: name,
                  type: 'ManyToOne',
                  isGroupable: foreign_key_field.is_a?(ColumnSchema) ? foreign_key_field.is_groupable : true
                }
              elsif field.is_a?(ColumnSchema)
                {
                  name: name,
                  type: field.column_type,
                  operators: field.filter_operators.to_a,
                  isGroupable: field.is_groupable
                }
              end
            end

            collection_result = {
              name: collection.name,
              fields: fields
            }

            if aggregation_capabilities
              collection_result[:aggregationCapabilities] = {
                supportGroups: aggregation_capabilities[:support_groups] && fields.any? { |f| f[:isGroupable] },
                supportedDateOperations: aggregation_capabilities[:supported_date_operations]
              }
            end

            collection_result
          end

          {
            content: {
              collections: result,
              nativeQueryConnections: connections,
              agentCapabilities: {
                canUseProjectionOnGetOne: true
              }
            },
            status: 200
          }
        end
      end
    end
  end
end
