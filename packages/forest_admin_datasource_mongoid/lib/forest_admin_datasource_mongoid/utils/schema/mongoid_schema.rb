module ForestAdminDatasourceMongoid
  module Utils
    module Schema
      class MongoidSchema
        include ForestAdminDatasourceToolkit::Exceptions
        attr_reader :is_array, :is_leaf, :fields

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
            # start_with?("$") useless ??
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
            handle.call(sub_prefix, schema) ? [field, *sub_fields] : sub_fields
          end
        end

        def get_sub_schema(path)
          # Terminating condition
          return self if path.blank?

          # General case: go down the tree
          prefix, suffix = path.split(/\.(.*)/)
          is_array = false
          is_leaf = false
          child = @fields[prefix]

          # Traverse relations
          if child.is_a?(Hash)
            relation_name = @model.relations[prefix].class_name

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
            raise ForestException, "Field '#{prefix}' not found. Available fields are: balbalblablalblalalbla"
          end

          # We ended up on a field => box it.
          if child.is_a? Mongoid::Fields::Standard
            child = { content: child }
            is_leaf = true
          end

          MongoidSchema.new(@model, child, is_array, is_leaf).get_sub_schema(suffix)
        end
      end
    end
  end
end
