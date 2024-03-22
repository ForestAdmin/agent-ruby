module ForestAdminDatasourceCustomizer
  module Decorators
    module Write
      module WriteReplace
        class WriteReplaceCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
          include ForestAdminDatasourceToolkit::Exceptions
          include ForestAdminDatasourceToolkit::Validations
          attr_reader :handlers

          def initialize(child_collection, datasource)
            super
            @handlers = {}
          end

          def replace_field_writing(field_name, definition)
            raise ForestException, 'A new writing method should be provided to replace field writing' unless definition

            ForestAdminDatasourceToolkit::Validations::FieldValidator.validate(self, field_name)
            @handlers[field_name] = definition

            mark_schema_as_dirty
          end

          def refine_schema(child_schema)
            schema = child_schema.dup
            schema[:fields] = child_schema[:fields].dup

            @handlers.each do |field_name, handler|
              schema[:fields][field_name].is_read_only = handler.nil?
            end

            schema
          end

          def create(caller, records)
            new_records = records.map do |record|
              rewrite_patch(caller, 'create', record)
            end

            child_collection.create(caller, new_records)
          end

          def update(caller, filter, patch)
            new_patch = rewrite_patch(caller, 'update', patch, [], filter)

            child_collection.update(caller, filter, new_patch)
          end

          # Takes a patch and recursively applies all rewriting rules to it.
          def rewrite_patch(caller, action, patch, used_handlers = [], filter = nil)
            # We rewrite the patch by applying all handlers on each field.
            context = WriteCustomizationContext.new(self, caller, action, patch, filter)
            patches = patch.map { |key| rewrite_key(context, key, used_handlers) }

            # We now have a list of patches (one per field) that we can merge.
            new_patch = deep_merge(*patches)

            # Check that the customer handlers did not introduce invalid data.
            RecordValidator.validate(self, new_patch) if new_patch.length.positive?

            new_patch
          end

          private

          def rewrite_key(context, key, used)
            if used.include?(key)
              raise ForestException,
                    "Conflict value on the field #{key}. It received several values."
            end

            record = context.record
            action = context.action
            caller = context.caller
            schema = schema.nil? ? nil : schema[:fields][key]

            if schema&.type == 'Column'
              # We either call the customer handler or a default one that does nothing.
              handler = @handlers[key] || ->(v) { { key => v } }
              field_patch = handler.call(record[key], context) || {}

              # Isolate change to our own value (which should not recurse) and the rest which should
              # trigger the other handlers.
              value = field_patch[key] || nil
              new_patch = rewrite_patch(caller, action, field_patch.except(key), used + [key])

              value ? deep_merge({ key => value }, new_patch) : new_patch
            elsif schema&.type == 'ManyToOne' || schema&.type == 'OneToOne'
              # Delegate relations to the appropriate collection.
              relation = datasource.get_collection(schema.foreign_collection)

              { key => relation.rewrite_patch(caller, action, record[key]) }
            else
              raise ForestException, "Unknown field: '#{key}'"
            end
          end

          # Recursively merge patches into a single one ensuring that there is no conflict.
          def deep_merge(*patches)
            acc = {}

            patches.each do |patch|
              patch = { patch => patch } unless patch.is_a?(Hash)

              patch.each do |sub_key, sub_value|
                if !acc.key?(sub_key)
                  acc[sub_key] = sub_value
                elsif sub_value.is_a?(Hash)
                  acc[sub_key] = deep_merge(acc[sub_key], sub_value)
                else
                  raise ForestException, "Conflict value on the field #{sub_key}. It received several values."
                end
              end
            end

            acc
          end
        end
      end
    end
  end
end
