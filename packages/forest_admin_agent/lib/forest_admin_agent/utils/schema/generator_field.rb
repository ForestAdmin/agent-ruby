module ForestAdminAgent
  module Utils
    module Schema
      class GeneratorField
        RELATION_MAP = {
          'ManyToMany' => 'BelongsToMany',
          'PolymorphicManyToOne' => 'BelongsTo',
          'ManyToOne' => 'BelongsTo',
          'OneToMany' => 'HasMany',
          'OneToOne' => 'HasOne'
        }.freeze

        def self.build_schema(collection, name)
          type = collection.schema[:fields][name].type

          schema = if type == 'Column'
                     build_column_schema(collection, name)
                   else
                     build_relation_schema(collection, name)
                   end

          schema.sort_by { |k, _v| k }.to_h
        end

        class << self
          private

          def build_column_schema(collection, name)
            column = collection.schema[:fields][name]
            is_foreign_key = ForestAdminDatasourceToolkit::Utils::Schema.foreign_key?(collection, name)

            {
              defaultValue: column.default_value,
              enums: column.enum_values.sort,
              field: name,
              integration: nil,
              inverseOf: nil,
              isFilterable: FrontendFilterable.filterable?(column.column_type, column.filter_operators),
              isPrimaryKey: column.is_primary_key,

              # When a column is a foreign key, it is readonly.
              # This may sound counter-intuitive: it is so that the user don't have two fields which
              # allow updating the same foreign key in the detail-view form (fk + many to one)
              isReadOnly: is_foreign_key || column.is_read_only,
              isRequired: column.validations.any? { |v| v[:operator] == 'Present' },
              isSortable: column.is_sortable,
              isVirtual: false,
              reference: nil,
              type: convert_column_type(column.column_type),
              validations: FrontendValidationUtils.convert_validation_list(column)
            }
          end

          def convert_column_type(type)
            return type if type.instance_of? String

            return [convert_column_type(type.first)] if type.instance_of? Array

            {
              fields: type.map do |key, sub_type|
                {
                  field: key,
                  type: convert_column_type(sub_type)
                }
              end
            }
          end

          def foreign_collection_filterable?(foreign_collection)
            foreign_collection.schema[:fields].values.any? do |field|
              field.type == 'Column' && FrontendFilterable.filterable?(field.column_type, field.filter_operators)
            end
          end

          def build_many_to_many_schema(relation, collection, foreign_collection, base_schema)
            target_name = relation.foreign_key_target
            target_field = foreign_collection.schema[:fields][target_name]
            through_schema = collection.datasource.get_collection(relation.through_collection)
            foreign_schema = through_schema.schema[:fields][relation.foreign_key]
            origin_key = through_schema.schema[:fields][relation.origin_key]

            base_schema.merge(
              {
                type: [target_field.column_type],
                defaultValue: nil,
                isFilterable: false,
                isPrimaryKey: false,
                isRequired: false,
                isReadOnly: origin_key.is_read_only || foreign_schema.is_read_only,
                isSortable: true,
                validations: [],
                reference: "#{foreign_collection.name}.#{target_name}"
              }
            )
          end

          def build_one_to_many_schema(relation, collection, foreign_collection, base_schema)
            target_name = relation.origin_key_target
            target_field = collection.schema[:fields][target_name]
            origin_key = foreign_collection.schema[:fields][relation.origin_key]

            base_schema.merge(
              {
                type: [target_field.column_type],
                defaultValue: nil,
                isFilterable: false,
                isPrimaryKey: false,
                isRequired: false,
                isReadOnly: origin_key.is_read_only,
                isSortable: true,
                validations: [],
                reference: "#{foreign_collection.name}.#{target_name}"
              }
            )
          end

          def build_one_to_one_schema(relation, collection, foreign_collection, base_schema)
            target_field = collection.schema[:fields][relation.origin_key_target]
            key_field = foreign_collection.schema[:fields][relation.origin_key]

            base_schema.merge(
              {
                type: key_field.column_type,
                defaultValue: nil,
                isFilterable: foreign_collection_filterable?(foreign_collection),
                isPrimaryKey: false,
                isRequired: false,
                isReadOnly: key_field.is_read_only,
                isSortable: target_field.is_sortable,
                validations: [],
                reference: "#{foreign_collection.name}.#{relation.origin_key_target}"
              }
            )
          end

          def build_many_to_one_schema(relation, collection, foreign_collection, base_schema)
            key_field = collection.schema[:fields][relation.foreign_key]

            base_schema.merge(
              {
                type: key_field.column_type,
                defaultValue: key_field.default_value,
                isFilterable: foreign_collection_filterable?(foreign_collection),
                isPrimaryKey: false,
                isRequired: key_field.validations.any? { |v| v[:operator] == 'Present' },
                isReadOnly: key_field.is_read_only,
                isSortable: key_field.is_sortable,
                validations: FrontendValidationUtils.convert_validation_list(key_field),
                reference: "#{foreign_collection.name}.#{relation.foreign_key_target}"
              }
            )
          end

          def build_polymorphic_many_to_one_schema(relation, base_schema)
            base_schema.merge(
              {
                type: 'Number', # default or take first foreign_key_targets ??,
                defaultValue: nil, # key_field.default_value,
                isFilterable: false, # foreign_collection_filterable?(foreign_collection),
                isPrimaryKey: false,
                isRequired: false, # key_field.validations.any? { |v| v[:operator] == 'Present' },
                isReadOnly: false, # key_field.is_read_only,
                isSortable: true, # key_field.is_sortable,
                validations: [], # FrontendValidationUtils.convert_validation_list(key_field),
                reference: "#{base_schema[:field]}.id", # to change
                polymorphic_referenced_models: relation.foreign_collections
              }
            )
          end

          def build_relation_schema(collection, name)
            relation = collection.schema[:fields][name]
            relation_schema = {
              field: name,
              enums: nil,
              integration: nil,
              isReadOnly: nil,
              isVirtual: false,
              relationship: RELATION_MAP[relation.type]
            }

            if relation.type == 'PolymorphicManyToOne'
              relation_schema[:inverseOf] = collection.name
              build_polymorphic_many_to_one_schema(relation, relation_schema)
            else
              relation_schema[:inverseOf] =
                ForestAdminDatasourceToolkit::Utils::Collection.get_inverse_relation(collection, name)
              foreign_collection = collection.datasource.get_collection(relation.foreign_collection)
              case relation.type
              when 'ManyToMany'
                build_many_to_many_schema(relation, collection, foreign_collection, relation_schema)
              when 'OneToMany', 'PolymorphicOneToMany'
                build_one_to_many_schema(relation, collection, foreign_collection, relation_schema)
              when 'OneToOne', 'PolymorphicOneToOne'
                build_one_to_one_schema(relation, collection, foreign_collection, relation_schema)
              when 'ManyToOne'
                build_many_to_one_schema(relation, collection, foreign_collection, relation_schema)
              end
            end
          end
        end
      end
    end
  end
end
