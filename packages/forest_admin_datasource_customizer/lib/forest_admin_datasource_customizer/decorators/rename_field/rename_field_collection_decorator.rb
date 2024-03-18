module ForestAdminDatasourceCustomizer
  module Decorators
    module RenameField
      class RenameFieldCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Decorators
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

          # Do not update arrays if renaming is a no-op (ie: customer is cancelling a previous rename)
          return unless initial_name != new_name

          from_child_collection[initial_name] = new_name
          to_child_collection[new_name] = initial_name
          mark_all_schema_as_dirty
        end

        def refine_schema(sub_schema)
          fields = {}

          sub_schema[:fields].each do |old_name, schema|
            case schema.type
            when 'ManyToOne'
              schema.foreign_key = from_child_collection[schema.foreign_key] || schema.foreign_key
            when 'OneToMany', 'OneToOne'
              relation = datasource.get_collection(schema.foreign_collection)
              schema.origin_key = relation.from_child_collection[schema.origin_key] || schema.origin_key
            when 'ManyToMany'
              through = datasource.get_collection(schema.through_collection)
              schema.foreign_key = through.from_child_collection[schema.foreign_key] || schema.foreign_key
              schema.origin_key = through.from_child_collection[schema.origin_key] || schema.origin_key
            end

            fields[from_child_collection[old_name] || old_name] = schema
          end

          sub_schema[:fields] = fields

          sub_schema
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
          record = super(
            caller,
            record_to_child_collection(data)
          )

          record_from_child_collection(record)
        end

        def list(caller, filter, projection)
          child_projection = projection.replace { |field| path_to_child_collection(field) }
          records = super(caller, filter, child_projection)
          return records if child_projection == projection

          records.map { |record| record_from_child_collection(record) }
        end

        def update(caller, filter, patch)
          super(caller, filter, record_to_child_collection(patch))
        end

        def aggregate(caller, filter, aggregation, limit = nil)
          rows = super(
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
            relation = datasource.get_collection(relation_schema.foreign_collection)

            return "#{relation_name}:#{relation.path_from_child_collection(paths[1])}"
          end

          from_child_collection[path] ||= path
        end

        # Convert field path from this collection to child collection
        def path_to_child_collection(path)
          if path.include?(':')
            paths = path.split(':')
            relation_name = paths[0]
            relation_schema = schema[:fields][relation_name]
            relation = datasource.get_collection(relation_schema.foreign_collection)
            child_field = to_child_collection[relation_name] || relation_name

            return "#{child_field}:#{relation.path_to_child_collection(paths[1])}"
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

            # Perform the mapping, recurse for relations
            if field_schema.type == 'Column' || value.nil?
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
