require 'faraday'
require 'json'

module ForestAdminAgent
  module Mcp
    class SchemaFetcher
      ONE_DAY_SECONDS = 24 * 60 * 60

      class << self
        def fetch_forest_schema(forest_server_url = nil)
          forest_server_url ||= Facades::Container.cache(:forest_server_url)
          now = Time.now.to_i

          # Return cached schema if still valid (less than 24 hours old)
          if @schema_cache && (now - @schema_cache[:fetched_at]) < ONE_DAY_SECONDS
            return @schema_cache[:schema]
          end

          env_secret = Facades::Container.cache(:env_secret)
          raise 'FOREST_ENV_SECRET is not set' unless env_secret

          client = Faraday.new(forest_server_url) do |conn|
            conn.headers['Content-Type'] = 'application/json'
            conn.headers['forest-secret-key'] = env_secret
          end

          response = client.get('/liana/forest-schema')

          unless response.success?
            raise "Failed to fetch forest schema: #{response.body}"
          end

          data = JSON.parse(response.body)
          collections = deserialize_collections(data)

          # Update cache
          @schema_cache = {
            schema: { collections: collections },
            fetched_at: now
          }

          { collections: collections }
        end

        def get_collection_names(schema)
          schema[:collections].map { |c| c[:name] }
        end

        def get_fields_of_collection(schema, collection_name)
          collection = schema[:collections].find { |c| c[:name] == collection_name }
          raise "Collection \"#{collection_name}\" not found in schema" unless collection

          collection[:fields]
        end

        def clear_cache!
          @schema_cache = nil
        end

        def set_cache(schema, fetched_at = nil)
          @schema_cache = {
            schema: schema,
            fetched_at: fetched_at || Time.now.to_i
          }
        end

        private

        def deserialize_collections(data)
          # Handle JSON:API format response
          return [] unless data['data'].is_a?(Array)

          included = data['included'] || []
          fields_by_id = build_fields_index(included)

          data['data'].map do |collection_data|
            attrs = collection_data['attributes'] || {}
            field_relationships = collection_data.dig('relationships', 'fields', 'data') || []

            fields = field_relationships.map do |field_ref|
              fields_by_id[field_ref['id']]
            end.compact

            {
              name: attrs['name'],
              fields: fields
            }
          end
        end

        def build_fields_index(included)
          index = {}
          included.each do |item|
            next unless item['type'] == 'forest-schema-fields'

            attrs = item['attributes'] || {}
            index[item['id']] = {
              field: attrs['field'],
              type: attrs['type'],
              is_filterable: attrs['isFilterable'],
              is_sortable: attrs['isSortable'],
              enum: attrs['enums'],
              inverse_of: attrs['inverseOf'],
              reference: attrs['reference'],
              is_read_only: attrs['isReadOnly'],
              is_required: attrs['isRequired'],
              integration: attrs['integration'],
              validations: attrs['validations'],
              default_value: attrs['defaultValue'],
              is_primary_key: attrs['isPrimaryKey']
            }
          end
          index
        end
      end
    end
  end
end
