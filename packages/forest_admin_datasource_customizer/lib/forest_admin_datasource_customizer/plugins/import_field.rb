module ForestAdminDatasourceCustomizer
  module Plugins
    class ImportField < Plugin
      include ForestAdminDatasourceToolkit::Exceptions
      include ForestAdminDatasourceCustomizer::Decorators::Computed

      def run(datasource_customizer, collection_customizer = nil, options = {})
        if options[:name].nil? || options[:path].nil?
          raise ForestAdminAgent::Http::Exceptions::BadRequestError,
                'The options parameter must contains the following keys: `name, path`'
        end

        options[:readonly] = false unless options.key?(:readonly)
        name = options[:name]
        result = options[:path].split(':').reduce({ collection: collection_customizer.name }) do |memo, field|
          collection = datasource_customizer.get_collection(memo[:collection])
          unless collection.schema[:fields].key?(field)
            raise ForestAdminAgent::Http::Exceptions::NotFoundError,
                  "Field #{field} not found in collection #{collection.name}"
          end

          to_one_relations = %w[ManyToOne OneToOne]
          field_schema = collection.schema[:fields][field]
          if field_schema.type == 'Column'
            { schema: field_schema }
          elsif to_one_relations.include?(field_schema.type)
            { collection: field_schema.foreign_collection }
          end
        end

        schema = result[:schema]
        collection_customizer.add_field(
          name,
          ComputedDefinition.new(
            column_type: schema.column_type,
            dependencies: [options[:path]],
            values: proc { |records|
              records.map { |record| ForestAdminDatasourceToolkit::Utils::Record.field_value(record, options[:path]) }
            },
            default_value: schema.default_value,
            enum_values: schema.enum_values
          )
        )

        unless options[:readonly] || schema.is_read_only
          collection_customizer.replace_field_writing(name) do |value|
            path = options[:path].split(':')
            writing_path = path.reduce({}) do |nested_path, current_path|
              nested_path[current_path] = path.index(current_path) == path.size - 1 ? value : {}
              nested_path[current_path]
            end

            writing_path
          end
        end

        if !options[:readonly] && schema.is_read_only
          raise ForestAdminAgent::Http::Exceptions::BadRequestError,
                "Readonly option should not be false because the field #{options[:path]} is not writable"
        end

        schema.filter_operators.each do |operator|
          collection_customizer.replace_field_operator(name, operator) do |value|
            { field: options[:path], operator: operator, value: value }
          end
        end

        return unless schema.is_sortable

        collection_customizer.replace_field_sorting(
          name,
          [{ field: options[:path], ascending: true }]
        )
      end
    end
  end
end
