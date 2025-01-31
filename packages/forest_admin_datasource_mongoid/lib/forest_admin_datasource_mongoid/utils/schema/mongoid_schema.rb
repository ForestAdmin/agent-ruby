module ForestAdminDatasourceMongoid
  module Utils
    module Schema
      class MongoidSchema
        attr_reader :is_array, :is_leaf, :fields

        def initialize(model, fields, is_array, is_leaf)
          @model = model
          @fields = fields
          @is_array = is_array
          @is_leaf = is_leaf
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
      end
    end
  end
end
