module ForestAdminDatasourceCustomizer
  module Decorators
    module Schema
      class SchemaCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Exceptions

        FILTER_DISABLEABLE_TYPES = %w[Column ManyToOne OneToOne].freeze

        def initialize(child_collection, datasource)
          super
          @schema_override = {}
          @unfilterable_fields = Set.new
        end

        def override_schema(value)
          @schema_override.merge!(value)
          mark_schema_as_dirty
        end

        def disable_field_filtering(name)
          field = child_collection.schema[:fields][name]

          raise ValidationError, "Field not found: '#{self.name}.#{name}'" if field.nil?

          unless FILTER_DISABLEABLE_TYPES.include?(field.type)
            raise ValidationError,
                  "Unexpected field type: '#{self.name}.#{name}' " \
                  "(found '#{field.type}' expected 'Column', 'ManyToOne' or 'OneToOne')"
          end

          if field.type == 'Column' && field.is_primary_key
            raise ValidationError, "Cannot disable filtering on primary key '#{self.name}.#{name}'"
          end

          @unfilterable_fields.add(name)
          mark_schema_as_dirty
        end

        def refine_schema(sub_schema)
          schema = sub_schema.merge(@schema_override)
          return schema if @unfilterable_fields.empty?

          schema[:fields] = schema[:fields].dup
          @unfilterable_fields.each { |name| schema[:fields][name] = unfilterable_copy(schema[:fields][name]) }

          schema
        end

        private

        # Field schemas are shared with the decorators below, which must keep filtering on this field.
        def unfilterable_copy(field)
          copy = field.dup

          if field.type == 'Column'
            copy.filter_operators = []
          else
            copy.is_filterable = false
          end

          copy
        end
      end
    end
  end
end
