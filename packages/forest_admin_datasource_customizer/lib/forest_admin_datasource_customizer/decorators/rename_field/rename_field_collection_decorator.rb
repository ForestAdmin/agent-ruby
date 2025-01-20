module ForestAdminDatasourceCustomizer
  module Decorators
    module RenameField
      class RenameFieldCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Decorators
        include ForestAdminDatasourceToolkit::Exceptions
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

        attr_accessor :from_child_collection, :to_child_collection

        def initialize(child_collection, datasource)
          super
          @from_child_collection = {}
          @to_child_collection = {}
        end

        def rename_field(current_name, new_name)
          unless schema[:fields][current_name]
            raise ForestAdminDatasourceToolkit::Exceptions::ForestException, "No such field '#{current_name}'"
          end

          initial_name = current_name

          ForestAdminDatasourceToolkit::Validations::FieldValidator.validate_name(name, new_name)

          @child_collection.schema[:fields].each do |field_name, field_schema|
            next unless field_schema.type == 'PolymorphicManyToOne' &&
                        [field_schema.foreign_key, field_schema.foreign_key_type_field].include?(current_name)

            raise ForestException, "Cannot rename '#{name}.#{current_name}', because it's implied " \
                                   "in a polymorphic relation '#{name}.#{field_name}'"
          end

          # Revert previous renaming (avoids conflicts and need to recurse on @to_child_collection).
          if to_child_collection[current_name]
            child_name = to_child_collection[current_name]
            to_child_collection.delete(current_name)
            from_child_collection.delete(child_name)
            initial_name = child_name
            mark_all_schema_as_dirty
          end

          # Do not update arrays if renaming is a no-op (ie: customer is cancelling a previous rename)
          return unless initial_name != new_name

          from_child_collection[initial_name] = new_name
          to_child_collection[new_name] = initial_name
          mark_all_schema_as_dirty
        end

        def refine_schema(sub_schema)
          fields = {}
          schema = sub_schema.dup

          # we don't handle schema modification for polymorphic many to one and reverse relations because
          # we forbid to rename foreign key and type fields on polymorphic many to one
          sub_schema[:fields].each do |old_name, old_schema|
            case old_schema.type
            when 'ManyToOne'
              relation = datasource.get_collection(old_schema.foreign_collection)
              old_schema.foreign_key = from_child_collection[old_schema.foreign_key] || old_schema.foreign_key
              old_schema.foreign_key_target =
                relation.from_child_collection[old_schema.foreign_key_target] || old_schema.foreign_key_target
            when 'OneToMany', 'OneToOne'
              relation = datasource.get_collection(old_schema.foreign_collection)
              old_schema.origin_key = relation.from_child_collection[old_schema.origin_key] || old_schema.origin_key
              old_schema.origin_key_target =
                from_child_collection[old_schema.origin_key_target] || old_schema.origin_key_target
            when 'ManyToMany'
              through = datasource.get_collection(old_schema.through_collection)
              relation = datasource.get_collection(old_schema.foreign_collection)
              old_schema.foreign_key = through.from_child_collection[old_schema.foreign_key] || old_schema.foreign_key
              old_schema.origin_key = through.from_child_collection[old_schema.origin_key] || old_schema.origin_key
              old_schema.origin_key_target =
                from_child_collection[old_schema.origin_key_target] || old_schema.origin_key_target
              old_schema.foreign_key_target =
                relation.from_child_collection[old_schema.foreign_key_target] || old_schema.foreign_key_target
            end

            fields[from_child_collection[old_name] || old_name] = old_schema
          end

          schema[:fields] = fields

          schema
        end

        def refine_filter(_caller, filter = nil)
          filter&.override(
            condition_tree: filter.condition_tree&.replace_fields do |field|
              path_to_child_collection(field)
            end,
            sort: filter.sort&.replace_clauses do |clause|
              {
                field: path_to_child_collection(clause[:field]),
                ascending: clause[:ascending]
              }
            end
          )
        end

        def create(caller, data)
          record = @child_collection.create(
            caller,
            record_to_child_collection(data)
          )

          record_from_child_collection(record)
        end

        def list(caller, filter, projection)
          child_projection = projection.replace { |field| path_to_child_collection(field) }
          records = @child_collection.list(caller, filter, child_projection)
          return records if child_projection.sort == projection.sort

          records.map { |record| record_from_child_collection(record) }
        end

        def update(caller, filter, patch)
          @child_collection.update(caller, filter, record_to_child_collection(patch))
        end

        def aggregate(caller, filter, aggregation, limit = nil)
          rows = @child_collection.aggregate(
            caller,
            filter,
            aggregation.replace_fields { |field| path_to_child_collection(field) },
            limit
          )

          rows.map do |row|
            {
              'value' => row['value'],
              'group' => row['group']&.reduce({}) do |memo, group|
                path, value = group
                memo.merge({ path_from_child_collection(path) => value })
              end
            }
          end
        end

        # rubocop:disable Lint/UselessMethodDefinition
        def mark_schema_as_dirty
          super
        end
        # rubocop:enable Lint/UselessMethodDefinition

        def mark_all_schema_as_dirty
          datasource.collections.each_value(&:mark_schema_as_dirty)
        end

        # Convert field path from child collection to this collection
        def path_from_child_collection(path)
          if path.include?(':')
            paths = path.split(':')
            child_field = paths[0]
            relation_name = from_child_collection[child_field] || child_field
            relation_schema = schema[:fields][relation_name]
            if relation_schema.type != 'PolymorphicManyToOne'
              relation = datasource.get_collection(relation_schema.foreign_collection)

              return "#{relation_name}:#{relation.path_from_child_collection(paths[1])}"
            end
          end

          from_child_collection[path] ||= path
        end

        # Convert field path from this collection to child collection
        def path_to_child_collection(path)
          if path.include?(':')
            paths = path.split(':')
            relation_name = paths[0]
            relation_schema = schema[:fields][relation_name]
            if relation_schema.type == 'PolymorphicManyToOne'
              relation_name = to_child_collection[relation_name] || relation_name

              return "#{relation_name}:#{paths[1]}"
            else
              relation = datasource.get_collection(relation_schema.foreign_collection)
              child_field = to_child_collection[relation_name] || relation_name

              return "#{child_field}:#{relation.path_to_child_collection(paths[1])}"
            end
          end

          to_child_collection[path] ||= path
        end

        # Convert record from this collection to the child collection
        def record_to_child_collection(record)
          child_record = {}
          record.each do |field, value|
            child_record[to_child_collection[field] || field] = value
          end

          child_record
        end

        def record_from_child_collection(child_record)
          record = {}
          child_record.each do |child_field, value|
            field = from_child_collection[child_field] || child_field
            field_schema = schema[:fields][field]

            # Perform the mapping, recurse for relation
            if field_schema.type == 'Column' || value.nil? || field_schema.type == 'PolymorphicManyToOne' ||
               field_schema.type == 'PolymorphicOneToOne'
              record[field] = value
            else
              relation = datasource.get_collection(field_schema.foreign_collection)
              record[field] = relation.record_from_child_collection(value)
            end
          end

          record
        end
      end
    end
  end
end
