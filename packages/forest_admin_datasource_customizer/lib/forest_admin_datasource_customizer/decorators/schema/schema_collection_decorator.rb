module ForestAdminDatasourceCustomizer
  module Decorators
    module Schema
      class SchemaCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        def initialize(child_collection, datasource)
          super
          @schema_override = {}
        end

        def override_schema(value)
          @schema_override.merge!(value)
          mark_schema_as_dirty
        end

        def refine_schema(sub_schema)
          sub_schema.merge(@schema_override)
        end
      end
    end
  end
end
