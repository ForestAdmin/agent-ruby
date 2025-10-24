module ForestAdminDatasourceMongoid
  module Utils
    module Schema
      class MongoidSchema
        include ForestAdminDatasourceToolkit::Exceptions
        include Utils::Helpers
        attr_reader :is_array, :is_leaf, :fields, :models

        def initialize(model, fields, is_array, is_leaf)
          @models = ObjectSpace.each_object(Class)
                               .select { |klass| klass < Mongoid::Document && klass.name && !klass.name.start_with?('Mongoid::') }
                               .to_h { |klass| [klass.name, klass] }
          @model = model
          @fields = fields
          @is_array = is_array
          @is_leaf = is_leaf
        end

        def schema_node
          @is_leaf ? @fields[:content] : @fields
        end

        def schema_type
          raise ForestAdminAgent::Http::Exceptions::UnprocessableError, 'Schema is not a leaf.' unless @is_leaf

          @fields[:content]
        end

        def self.from_model(model)
          fields = fields_and_embedded_relations(model)

          new(model, build_fields(fields), false, false)
        end

        def self.fields_and_embedded_relations(model)
          embedded_class = [Mongoid::Association::Embedded::EmbedsMany, Mongoid::Association::Embedded::EmbedsOne]
          relations = model.relations.select { |_name, association| embedded_class.include?(association.class) }

          model.fields.merge(relations)
        end

        def self.build_fields(schema_fields, level = 0)
          targets = {}

          schema_fields.each do |name, field|
            next if name.start_with?('$') || name.include?('__') || (name == '_id' && level.positive?)

            if VersionManager.sub_document?(field)
              sub_targets = build_fields(fields_and_embedded_relations(field.klass), level + 1)
              sub_targets.each { |sub_name, sub_field| recursive_set(targets, "#{name}.#{sub_name}", sub_field) }
            elsif VersionManager.sub_document_array?(field)
              sub_targets = build_fields(fields_and_embedded_relations(field.klass), level + 1)
              sub_targets.each { |sub_name, sub_field| recursive_set(targets, "#{name}.[].#{sub_name}", sub_field) }
            else
              recursive_set(targets, name, field)
            end
          end

          targets
        end

        def self.recursive_set(target, path, value)
          index = path.index('.')
          if index.nil?
            target[path] = value
          else
            prefix = path[0, index]
            suffix = path[index + 1, path.length]
            target[prefix] ||= {}
            recursive_set(target[prefix], suffix, value)
          end
        end

        def list_paths_matching(handle, prefix = nil)
          return [] if @is_leaf

          @fields.keys
                 .filter(&:present?)
                 .flat_map do |field|
            schema = get_sub_schema(field)
            sub_prefix = prefix ? "#{prefix}.#{field}" : field
            sub_fields = schema.list_paths_matching(handle, sub_prefix)
            sub_fields.map { |sub_field| "#{field}.#{sub_field}" }
            # debugger
            handle.call(sub_prefix, schema) ? [sub_prefix, *sub_fields] : sub_fields
          end
        end

        def get_sub_schema(path)
          # Terminating condition
          return self if path.blank?

          # General case: go down the tree
          prefix, suffix = path.split(/\.(.*)/)
          is_leaf = false
          child = @fields[prefix]
          is_array = child.is_a?(Mongoid::Fields::Standard) && child.options[:type] == Array

          # Traverse relations
          if child.is_a?(Hash)
            relation_name = @model.relations[prefix].class_name

            unless @models.key?(relation_name)
              raise ForestAdminAgent::Http::Exceptions::NotFoundError, "Collection '#{relation_name}' not found."
            end

            # Traverse arrays
            if child.is_a?(Hash) && child['[]']
              # (has_many embed)
              child = child['[]']
              is_array = true
            else
              # (has_one embed)
              child = MongoidSchema.from_model(@models[relation_name]).fields
            end

            return MongoidSchema.new(@models[relation_name], child, is_array, is_leaf).get_sub_schema(suffix)
          elsif child.nil?
            raise ForestAdminAgent::Http::Exceptions::NotFoundError, "Field '#{prefix}' not found. Available fields are: #{list_fields}"
          end

          # We ended up on a field => box it.
          if child.is_a? Mongoid::Fields::Standard
            child = { content: child }
            is_leaf = true
          end

          MongoidSchema.new(@model, child, is_array, is_leaf).get_sub_schema(suffix)
        end

        def apply_stack(stack, skip_as_models: false)
          raise ForestAdminAgent::Http::Exceptions::BadRequestError, 'Stack can never be empty.' if stack.empty?

          step = stack.pop
          sub_schema = get_sub_schema(step[:prefix])

          step[:as_fields].each do |field|
            field_schema = sub_schema.get_sub_schema(field)
            recursive_delete(sub_schema.fields, field)

            sub_schema.fields[field.gsub('.', '@@@')] = if field_schema.is_array
                                                          { '[]' => field_schema.schema_node }
                                                        else
                                                          field_schema.schema_node
                                                        end
          end

          unless stack.empty?
            sub_schema.fields['_id'] = Mongoid::Fields::Standard.new('__placeholder__', { type: String })
            sub_schema.fields['parent'] = apply_stack(stack).fields
            sub_schema.fields['parent_id'] = sub_schema.fields['parent']['_id']
          end

          if skip_as_models
            # Here we actually should recurse into the subSchema and add the _id and parentId fields
            # to the virtual one-to-one relations.
            #
            # The issue is that we can't do that because we don't know where the relations are after
            # the first level of nesting (we would need to have the complete asModel / asFields like in
            # the datasource.ts file).
            #
            # Because of that, we need to work around the missing fields in:
            # - pipeline/virtual-fields.ts file: we're throwing an error when we can't guess the value
            #   of a given _id / parentId field.
            # - pipeline/filter.ts: we're using an educated guess for the types of the _id / parentId
            #   fields (String or ObjectId)
          else
            step[:as_models].each do |field|
              recursive_delete(@fields, field)
            end
          end

          stack << step

          sub_schema
        end

        # List leafs and arrays up to a certain level
        # Arrays are never traversed
        def list_fields(level = Float::INFINITY)
          if @is_leaf
            raise ForestAdminAgent::Http::Exceptions::UnprocessableError, 'Cannot list fields on a leaf schema.'
          end
          raise ForestAdminAgent::Http::Exceptions::BadRequestError, 'Level must be greater than 0.' if level.zero?

          return @fields.keys if level == 1

          @fields.keys.flat_map do |field|
            schema = get_sub_schema(field)
            if schema.is_leaf || schema.is_array
              [field]
            else
              schema.list_fields(level - 1).map { |sub_field| "#{field}.#{sub_field}" }
            end
          end
        end
      end
    end
  end
end
