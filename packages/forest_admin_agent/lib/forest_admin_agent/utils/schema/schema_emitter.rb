require 'digest/sha1'
require 'json'

module ForestAdminAgent
  module Utils
    module Schema
      class SchemaEmitter
        LIANA_NAME = "agent-ruby"
        LIANA_VERSION = "1.12.15"

        def self.generate(datasource)
          datasource.collections
                    .map { |_name, collection| GeneratorCollection.build_schema(collection) }
                    .sort_by { |collection| collection[:name] }
        end

        def self.meta
          {
            liana: LIANA_NAME,
            liana_version: LIANA_VERSION,
            stack: {
              engine: 'ruby',
              engine_version: RUBY_VERSION
            }
          }
        end

        def self.serialize(schema)
          hash = Digest::SHA1.hexdigest(schema[:collections].to_json)
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
            included: included.reject!(&:empty?)&.flatten || [],
            meta: schema[:meta].merge(schemaFileHash: hash)
          }
        end

        def self.get_smart_features_by_collection(type, data, with_attributes: false)
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
