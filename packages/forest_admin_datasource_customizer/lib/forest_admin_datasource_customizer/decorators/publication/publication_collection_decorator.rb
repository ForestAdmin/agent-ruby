module ForestAdminDatasourceCustomizer
  module Decorators
    module Publication
      class PublicationCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Exceptions
        attr_reader :blacklist

        def initialize(child_collection, datasource)
          super
          @blacklist = []
        end

        def change_field_visibility(name, visible)
          field = child_collection.schema[:fields][name]
          raise ForestException, "No such field '#{name}'" unless field
          raise ForestException, 'Cannot hide primary key' if ForestAdminDatasourceToolkit::Utils::Schema.primary_key?(
            child_collection, name
          )

          if visible
            @blacklist.delete(name)
          else
            @blacklist << name
          end

          mark_schema_as_dirty
        end

        def create(caller, data)
          record = {}
          child_collection.create(caller, data).each do |key, value|
            record[key] = value unless @blacklist.include?(key)
          end

          record
        end

        def refine_schema(child_schema)
          fields = {}
          schema = child_schema.dup

          schema[:fields].each do |name, field|
            fields[name] = field if published?(name)
          end

          schema[:fields] = fields

          schema
        end

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

          if field.type == 'ManyToMany'
            return (
              datasource.published?(field.through_collection) &&
              datasource.published?(field.foreign_collection) &&
              datasource.get_collection(field.through_collection).published?(field.foreign_key) &&
              datasource.get_collection(field.through_collection).published?(field.origin_key) &&
              published?(field.origin_key_target) &&
              datasource.get_collection(field.foreign_collection).published?(field.foreign_key_target)
            )
          end

          true
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
