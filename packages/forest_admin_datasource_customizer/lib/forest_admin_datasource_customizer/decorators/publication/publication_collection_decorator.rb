module ForestAdminDatasourceCustomizer
  module Decorators
    module Publication
      class PublicationCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Utils
        include ForestAdminDatasourceToolkit::Exceptions
        attr_reader :blacklist

        def initialize(child_collection, datasource)
          super
          @blacklist = []
        end

        def change_field_visibility(name, visible)
          field = child_collection.schema[:fields][name]
          raise ForestException, "No such field '#{name}'" unless field
          raise ForestException, 'Cannot hide primary key' if Schema.primary_key?(child_collection.schema, name)

          if visible
            @blacklist.delete(name)
          else
            @blacklist << name
          end

          mark_schema_as_dirty
        end

        def create(caller, data)
          super.map do |child_record|
            record = {}
            child_record.each do |key, value|
              record[key] = value unless @blacklist.include?(key)
            end
            record
          end
        end

        def refine_schema(child_schema)
          child_schema[:fields].each do |name, schema|
            child_schema[:fields][name] = schema unless @blacklist.include?(name)
          end

          child_schema
        end

        # public override markSchemaAsDirty(): void {
        #     return super.markSchemaAsDirty();
        #   }

        private

        def published?(name)
          # Explicitly hidden
          return false if @blacklist.include?(name)

          # Implicitly hidden
          field = child_collection.schema[:fields][name]

          if field.type == 'ManyToOne'
            return (
              datasource.published?(field.foreign_collection) &&
              published?(field.foreign_key) &&
              datasource.get_collection(field.foreign_collection).published?(field.foreign_key_target)
            )
          end

          if field.type == 'OneToOne' || field.type == 'OneToMany'
            return (
              datasource.published?(field.foreign_collection) &&
              datasource.get_collection(field.foreign_collection).published?(field.origin_key) &&
              published?(field.origin_key_target)
            )
          end

          return false unless field.type == 'ManyToMany'

          datasource.published?(field.through_collection) &&
            datasource.published?(field.foreign_collection) &&
            datasource.get_collection(field.through_collection).published?(field.foreign_key) &&
            datasource.get_collection(field.through_collection).published?(field.origin_key) &&
            published?(field.origin_key_target) &&
            datasource.get_collection(field.foreign_collection).published?(field.foreign_key_target)
        end
      end
    end
  end
end
