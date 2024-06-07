require 'digest/sha1'
require 'json'

module ForestAdminAgent
  module Utils
    module Schema
      class SchemaEmitter
        LIANA_NAME = "forest-rails"

        LIANA_VERSION = "1.0.0-beta.52"

        def self.get_serialized_schema(datasource)
          schema_path = Facades::Container.cache(:schema_path)
          if Facades::Container.cache(:is_production)
            schema = if schema_path && File.exist?(schema_path)
                       JSON.parse(File.read(schema_path), { symbolize_names: true })
                     else
                       ForestAdminAgent::Facades::Container.logger.log(
                         'Warn',
                         'The .forestadmin-schema.json file doesn\'t exist'
                       )

                       {
                         meta: meta(Digest::SHA1.hexdigest('')),
                         collections: {}
                       }
                     end
          else
            schema = generate(datasource)
            hash = Digest::SHA1.hexdigest(schema.to_json)
            schema = {
              meta: meta(hash),
              collections: schema
            }

            File.write(schema_path, JSON.pretty_generate(schema))
          end

          serialize(schema)
        end

        class << self
          private

          def generate(datasource)
            datasource.collections
                      .map { |_name, collection| GeneratorCollection.build_schema(collection) }
                      .sort_by { |collection| collection[:name] }
          end

          def meta(hash)
            {
              liana: LIANA_NAME,
              liana_version: LIANA_VERSION,
              stack: {
                engine: 'ruby',
                engine_version: RUBY_VERSION
              },
              schemaFileHash: hash
            }
          end

          def serialize(schema)
            data = []
            included = []
            schema[:collections].each do |collection|
              collection_actions = collection[:actions]
              collection_segments = collection[:segments]
              collection.delete(:actions)
              collection.delete(:segments)

              included << get_smart_features_by_collection('actions', collection_actions, with_attributes: true)
              included << get_smart_features_by_collection('segments', collection_segments, with_attributes: true)

              data.push(
                {
                  id: collection[:name],
                  type: 'collections',
                  attributes: collection,
                  relationships: {
                    actions: { data: get_smart_features_by_collection('actions', collection_actions) },
                    segments: { data: get_smart_features_by_collection('segments', collection_segments) }
                  }
                }
              )
            end

            {
              data: data,
              included: included.reject!(&:empty?)&.flatten,
              meta: schema[:meta]
            }
          end

          def get_smart_features_by_collection(type, data, with_attributes: false)
            smart_features = []
            data.each do |value|
              smart_feature = { id: value[:id], type: type }
              smart_feature[:attributes] = value if with_attributes
              smart_features << smart_feature
            end

            smart_features
          end
        end
      end
    end
  end
end
