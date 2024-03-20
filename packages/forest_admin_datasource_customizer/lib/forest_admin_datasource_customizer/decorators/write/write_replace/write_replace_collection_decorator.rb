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
              schema[:fields][field_name] = schema[:fields][field_name].merge(isReadOnly: handler.nil?)
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
        end
      end
    end
  end
end
