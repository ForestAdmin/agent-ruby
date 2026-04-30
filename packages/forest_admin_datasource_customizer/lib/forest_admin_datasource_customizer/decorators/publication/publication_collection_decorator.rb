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

          @child_collection.schema[:fields].each do |field_name, field_schema|
            next unless field_schema.type == 'PolymorphicManyToOne' &&
                        [field_schema.foreign_key, field_schema.foreign_key_type_field].include?(name)

            raise ForestException, "Cannot remove field '#{self.name}.#{name}', because it's implied " \
                                   "in a polymorphic relation '#{self.name}.#{field_name}'"
          end
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

        def published?(name, visited = nil)
          # Track visited collection:field pairs to prevent infinite recursion
          # when checking bidirectional relations (e.g., users -> orders -> users)
          visited ||= Set.new
          visit_key = "#{self.name}:#{name}"
          return true if visited.include?(visit_key)

          visited.add(visit_key)

          # Explicitly hidden
          return false if @blacklist.include?(name)

          # Implicitly hidden
          field = child_collection.schema[:fields][name]

          if field.nil?
            message = "Field '#{name}' not found in schema of collection '#{self.name}'"
            ForestAdminAgent::Facades::Container.logger.log('Warn', message)
            return false
          end

          return check_many_to_one_published?(field, visited) if field.type == 'ManyToOne'

          if %w[OneToOne OneToMany PolymorphicOneToOne PolymorphicOneToMany].include?(field.type)
            return check_one_to_x_published?(field, visited)
          end

          return check_many_to_many_published?(field, visited) if field.type == 'ManyToMany'

          true
        end

        # rubocop:disable Lint/UselessMethodDefinition
        def mark_schema_as_dirty
          super
        end
        # rubocop:enable Lint/UselessMethodDefinition

        private

        def check_many_to_one_published?(field, visited)
          return false unless datasource.published?(field.foreign_collection)
          return false unless published?(field.foreign_key, visited)

          foreign_collection = datasource.get_collection(field.foreign_collection)
          unless foreign_collection.child_collection.schema[:fields].key?(field.foreign_key_target)
            log_missing_field(field.foreign_collection, field.foreign_key_target, 'foreign_key_target')
            return false
          end

          foreign_collection.published?(field.foreign_key_target, visited)
        end

        def check_one_to_x_published?(field, visited)
          return false unless datasource.published?(field.foreign_collection)

          foreign_collection = datasource.get_collection(field.foreign_collection)
          unless foreign_collection.child_collection.schema[:fields].key?(field.origin_key)
            log_missing_field(field.foreign_collection, field.origin_key, 'origin_key')
            return false
          end

          return false unless foreign_collection.published?(field.origin_key, visited)

          unless child_collection.schema[:fields].key?(field.origin_key_target)
            log_missing_field(name, field.origin_key_target, 'origin_key_target')
            return false
          end

          published?(field.origin_key_target, visited)
        end

        def check_many_to_many_published?(field, visited)
          return false unless datasource.published?(field.through_collection)
          return false unless datasource.published?(field.foreign_collection)

          through_collection = datasource.get_collection(field.through_collection)
          foreign_collection = datasource.get_collection(field.foreign_collection)

          unless through_collection.child_collection.schema[:fields].key?(field.foreign_key)
            log_missing_field(field.through_collection, field.foreign_key, 'foreign_key')
            return false
          end

          unless through_collection.child_collection.schema[:fields].key?(field.origin_key)
            log_missing_field(field.through_collection, field.origin_key, 'origin_key')
            return false
          end

          unless child_collection.schema[:fields].key?(field.origin_key_target)
            log_missing_field(name, field.origin_key_target, 'origin_key_target')
            return false
          end

          unless foreign_collection.child_collection.schema[:fields].key?(field.foreign_key_target)
            log_missing_field(field.foreign_collection, field.foreign_key_target, 'foreign_key_target')
            return false
          end

          through_collection.published?(field.foreign_key, visited) &&
            through_collection.published?(field.origin_key, visited) &&
            published?(field.origin_key_target, visited) &&
            foreign_collection.published?(field.foreign_key_target, visited)
        end

        def log_missing_field(collection_name, field_name, field_type)
          message = "Field '#{field_name}' (#{field_type}) not found in schema of collection '#{collection_name}'. " \
                    'This relation will be hidden. Check if the field exists in your database.'
          ForestAdminAgent::Facades::Container.logger.log('Warn', message)
        end
      end
    end
  end
end
