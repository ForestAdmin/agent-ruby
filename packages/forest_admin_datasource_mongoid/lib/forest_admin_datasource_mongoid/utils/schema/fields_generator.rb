module ForestAdminDatasourceMongoid
  module Utils
    module Schema
      class FieldsGenerator
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
        extend Utils::Helpers
        extend Parser::Column

        def self.build_fields_schema(model, stack)
          our_schema = {}
          child_schema = MongoidSchema.from_model(model).apply_stack(stack)

          child_schema.fields.each do |name, field|
            next unless name != 'parent'

            default_value = if field.respond_to?(:object_id_field?) && field.object_id_field?
                              nil
                            else
                              get_default_value(field)
                            end

            our_schema[name] = ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
              column_type: get_column_type(field),
              filter_operators: operators_for_column_type(get_column_type(field)),
              is_primary_key: name == '_id',
              is_read_only: false,
              is_sortable: get_column_type(field) != 'Json',
              default_value: default_value,
              enum_values: [],
              validations: [] # get_validations(field)
            )

            if !field.is_a?(Hash) && field.foreign_key? && field.type != Array && !field.association.polymorphic?
              our_schema["#{name}__many_to_one"] = build_many_to_one(field)
            end
          end

          return our_schema unless stack.length > 1

          parent_prefix = stack[stack.length - 2][:prefix]

          our_schema['_id'] = build_virtual_primary_key
          parent_id = child_schema.fields['parent']['_id']
          our_schema['parent_id'] = ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
            column_type: get_column_type(parent_id),
            filter_operators: operators_for_column_type(get_column_type(parent_id)),
            is_primary_key: false,
            is_read_only: false,
            is_sortable: get_column_type(parent_id) != 'Json',
            default_value: parent_id.object_id_field? ? nil : get_default_value(parent_id),
            enum_values: [],
            validations: [{ operator: 'Present' }]
          )

          model_name = model.name.gsub('::', '__')
          our_schema['parent'] = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema.new(
            foreign_collection: escape(parent_prefix.nil? ? model_name : "#{model_name}.#{parent_prefix}"),
            foreign_key: 'parent_id',
            foreign_key_target: '_id'
          )

          our_schema
        end

        def self.build_virtual_primary_key
          ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
            column_type: 'String',
            filter_operators: operators_for_column_type('String'),
            is_primary_key: true,
            is_read_only: true,
            is_sortable: true
          )
        end

        def self.build_many_to_one(field)
          association = field.options[:association]
          ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema.new(
            foreign_collection: association.klass.name.gsub('::', '__'),
            foreign_key: association.foreign_key,
            foreign_key_target: '_id'
          )
        end
      end
    end
  end
end
