module ForestAdminDatasourceCustomizer
  module Decorators
    module RenameCollection
      class RenameCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Decorators
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

        def name
          datasource.get_collection_name(super)
        end

        def list(caller, filter = nil, projection = nil)
          refined_filter = refine_filter(caller, filter)

          # Pass the decorated datasource and disable_includes flag via caller.request
          # This allows the ActiveRecord collection to resolve renamed collections correctly
          if caller
            request = caller.instance_variable_get(:@request) || {}
            # Pass the top-level datasource (with renames) for collection resolution
            request[:decorated_datasource] = datasource
            # Mark if we need to disable includes for polymorphic relations
            # to avoid Api::Api::Income errors caused by polymorphic_class_for
            request[:disable_polymorphic_includes] = true if polymorphic_relations?
          end

          records = @child_collection.list(caller, refined_filter, projection)

          transform_records_polymorphic_values(records)
        end

        def create(caller, data)
          transformed_data = transform_data_polymorphic_values(data)
          result = @child_collection.create(caller, transformed_data)

          transform_record_polymorphic_values(result)
        end

        def update(caller, filter, patch)
          refined_filter = refine_filter(caller, filter)
          transformed_patch = transform_data_polymorphic_values(patch)

          @child_collection.update(caller, refined_filter, transformed_patch)
        end

        def refine_filter(_caller, filter)
          return filter unless filter&.condition_tree

          type_fields = polymorphic_type_fields

          transformed_tree = filter.condition_tree.replace_leafs do |leaf|
            if type_fields.include?(leaf.field)
              transformed_value = transform_polymorphic_value(leaf.value)
              if transformed_value == leaf.value
                leaf
              else
                leaf.override(value: transformed_value)
              end
            else
              leaf
            end
          end

          filter.override(condition_tree: transformed_tree)
        end

        private

        def polymorphic_relations?
          # Check self.schema (the decorator's schema) instead of @child_collection.schema
          # because self.schema includes all transformations from the decorator chain
          return false unless schema && schema[:fields]

          schema[:fields].any? do |_name, field_schema|
            field_schema&.type&.start_with?('Polymorphic')
          end
        end

        def polymorphic_type_fields
          type_fields = []
          child_schema = @child_collection.schema
          return type_fields unless child_schema && child_schema[:fields]

          child_schema[:fields].each_value do |field_schema|
            case field_schema.type
            when 'PolymorphicManyToOne'
              type_fields << field_schema.foreign_key_type_field
            end
          end
          type_fields
        end

        def transform_data_polymorphic_values(data)
          return data unless data

          type_fields = polymorphic_type_fields
          transformed_data = data.dup

          type_fields.each do |type_field|
            next unless transformed_data.key?(type_field)

            original_value = transformed_data[type_field]
            transformed_value = reverse_collection_name(original_value)
            transformed_data[type_field] = transformed_value if transformed_value != original_value
          end

          transformed_data
        end

        def transform_polymorphic_value(value)
          return value unless value

          # Handle both single values and arrays (for IN/NOT_IN operators)
          if value.is_a?(Array)
            value.map { |v| reverse_collection_name(v) }
          else
            reverse_collection_name(value)
          end
        end

        def reverse_collection_name(collection_name)
          return nil if collection_name.nil?

          to_child_name = datasource.instance_variable_get(:@to_child_name)
          formatted_name = to_child_name[collection_name] || collection_name
          formatted_name.gsub('__', '::')
        end

        def forward_collection_name(collection_name)
          return nil if collection_name.nil?

          from_child_name = datasource.instance_variable_get(:@from_child_name)
          formatted_name = collection_name.gsub('::', '__')
          from_child_name[formatted_name] || collection_name
        end

        def transform_records_polymorphic_values(records)
          return records unless records.is_a?(Array)

          type_fields = polymorphic_type_fields
          return records if type_fields.empty?

          records.map do |record|
            transform_record_polymorphic_values(record)
          end
        end

        def transform_record_polymorphic_values(record)
          return record unless record.is_a?(Hash)

          type_fields = polymorphic_type_fields
          return record if type_fields.empty?

          transformed_record = record.dup

          type_fields.each do |type_field|
            next unless transformed_record.key?(type_field)

            old_value = transformed_record[type_field]
            new_value = forward_collection_name(old_value)
            transformed_record[type_field] = new_value if new_value != old_value
          end

          transformed_record
        end

        protected

        def refine_schema(sub_schema)
          current_collection_name = @child_collection.name

          sub_schema[:fields].each_value do |old_schema|
            case old_schema.type
            when 'PolymorphicOneToOne', 'PolymorphicOneToMany'
              refine_polymorphic_one_schema(old_schema, current_collection_name)
            when 'PolymorphicManyToOne'
              refine_polymorphic_many_schema(old_schema)
            when 'ManyToOne', 'OneToMany', 'OneToOne', 'ManyToMany'
              refine_standard_relation_schema(old_schema)
            end
          end

          sub_schema
        end

        def refine_polymorphic_one_schema(schema, current_collection_name)
          if schema.origin_type_value == current_collection_name
            schema.origin_type_value = datasource.get_collection_name(current_collection_name)
          end
          schema.foreign_collection = datasource.get_collection_name(schema.foreign_collection)
        end

        def refine_polymorphic_many_schema(schema)
          schema.foreign_collections = schema.foreign_collections.map { |fc| datasource.get_collection_name(fc) }
          schema.foreign_key_targets = schema.foreign_key_targets.transform_keys do |key|
            datasource.get_collection_name(key)
          end
        end

        def refine_standard_relation_schema(schema)
          schema.foreign_collection = datasource.get_collection_name(schema.foreign_collection)
          return unless schema.type == 'ManyToMany'

          schema.through_collection = datasource.get_collection_name(schema.through_collection)
        end

        public

        # rubocop:disable Lint/UselessMethodDefinition
        def mark_schema_as_dirty
          super
        end
        # rubocop:enable Lint/UselessMethodDefinition
      end
    end
  end
end
