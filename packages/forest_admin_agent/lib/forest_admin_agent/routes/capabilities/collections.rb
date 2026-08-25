require 'json'
module ForestAdminAgent
  module Routes
    module Capabilities
      class Collections < AbstractAuthenticatedRoute
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
          context = build(args)
          datasource = context.datasource
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
                canUseProjectionOnGetOne: true,
                canUseProjectionViaHeader: true,
                canUseProjectionViaHeaderOnList: true,
                canUseMultipleFieldsProjectionOnRelation: true,
                canUseAuditTrail: audit_trail_enabled?
              }
            },
            status: 200
          }
        end

        private

        # True only where the store the record-history route reads from exists — the same lookup that route
        # mounts itself on, so the capability cannot drift from what the routes actually serve. The front gates
        # its History tab on this.
        def audit_trail_enabled?
          !::ForestAdminAgent::AuditTrail.store.nil?
        end
      end
    end
  end
end
