module ForestAdminDatasourceToolkit
  module Validations
    class FieldValidator
      include ForestAdminDatasourceToolkit::Schema

      def self.validate(collection, field, values = nil)
        dot_index = field.index(':')

        if dot_index.nil?
          schema = collection.schema[:fields][field]

          raise Exceptions::ValidationError, "Column not found: '#{collection.name}.#{field}'" if schema.nil?

          if schema.type != 'Column'
            raise Exceptions::ValidationError,
                  "Unexpected field type: '#{collection.name}.#{field}' (found '#{schema.type}' expected 'Column')"
          end

          if values.is_a?(Array)
            values.each do |value|
              validate_value(field, schema, value)
            end
          end
        else
          prefix, suffix = field.split(':')
          schema = collection.schema[:fields][prefix]

          raise Exceptions::ValidationError, "Relation not found: '#{collection.name}.#{prefix}'" if schema.nil?

          if schema.type == 'PolymorphicManyToOne' && suffix != '*'
            raise Exceptions::ValidationError, "Unexpected nested field #{suffix} under generic relation: #{collection.name}.#{prefix}"
          end

          if schema.type != 'ManyToOne' && schema.type != 'OneToOne' && schema.type != 'PolymorphicManyToOne' &&
             schema.type != 'PolymorphicOneToOne'
            raise Exceptions::ValidationError,
                  "Unexpected field type: '#{collection.name}.#{prefix}' (found '#{schema.type}')"
          end

          if schema.type != 'PolymorphicManyToOne'
            suffix = field[dot_index + 1, field.length - dot_index - 1]
            association = collection.datasource.get_collection(schema.foreign_collection)
            validate(association, suffix, values)
          end
        end
      end

      def self.validate_value_for_id(field, schema, value)
        validate_value(field, schema, value, [schema.column_type])
      end

      def self.validate_value(field, schema, value, allowed_types = nil)
        allowed_types ||= Rules.get_allowed_types_for_column_type(schema.column_type)

        # TODO: FIXME: handle complex type from ColumnType
        # if schema.column_type != PrimitiveType::STRING
        # end

        type = TypeGetter.get(value, schema.column_type)

        unless allowed_types.include?(type)
          raise Exceptions::ValidationError,
                "The given value has a wrong type for '#{field}': #{value}.\n Expects #{allowed_types}"
        end

        return unless value && schema.column_type == PrimitiveType::ENUM

        check_enum_value(schema, value)
      end

      def self.validate_name(collection_name, name)
        return unless name.include?(' ')

        sanitized_name = name.gsub(/ (.)/, &:upcase)
        raise Exceptions::ValidationError,
              "The name of field '#{name}' you configured on '#{collection_name}' must not contain space. Something like '#{sanitized_name}' should work has expected."
      end

      def self.check_enum_value(column_schema, enum_value)
        is_enum_allowed = column_schema.enum_values.include?(enum_value)

        return if is_enum_allowed

        raise Exceptions::ValidationError,
              "The given enum value(s) #{enum_value} is not listed in #{column_schema.enum_values}"
      end
    end
  end
end
