module ForestAdminDatasourceCustomizer
  module Plugins
    class AddExternalRelation < Plugin
      include ForestAdminDatasourceToolkit::Exceptions
      include ForestAdminDatasourceCustomizer::Decorators::Computed

      def run(_datasource_customizer, collection_customizer = nil, options = {})
        primary_keys = ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(collection_customizer.collection)

        unless options.key?(:name) && options.key?(:schema) && options.key?(:listRecords)
          raise ForestAdminAgent::Http::Exceptions::BadRequestError,
                'The options parameter must contains the following keys: `name, schema, listRecords`'
        end

        collection_customizer.add_field(
          options[:name],
          ComputedDefinition.new(
            column_type: [options[:schema]],
            dependencies: options[:dependencies] || primary_keys,
            values: proc { |records, context|
              records.map { |record| options[:listRecords].call(record, context) }
            }
          )
        )
      end
    end
  end
end
