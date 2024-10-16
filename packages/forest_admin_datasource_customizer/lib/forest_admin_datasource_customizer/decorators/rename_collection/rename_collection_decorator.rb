module ForestAdminDatasourceCustomizer
  module Decorators
    module RenameCollection
      class RenameCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Decorators
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

        def name
          datasource.get_collection_name(super)
        end

        def refine_schema(sub_schema)
          fields = {}

          sub_schema[:fields].each do |name, old_schema|
            if old_schema.type != 'Column' && old_schema.type != 'PolymorphicManyToOne'
              old_schema.foreign_collection = datasource.get_collection_name(old_schema.foreign_collection)
              if old_schema.type == 'ManyToMany'
                old_schema.through_collection = datasource.get_collection_name(old_schema.through_collection)
              end
            end

            fields[name] = old_schema
          end

          sub_schema
        end

        # rubocop:disable Lint/UselessMethodDefinition
        def mark_schema_as_dirty
          super
        end
        # rubocop:enable Lint/UselessMethodDefinition
      end
    end
  end
end
