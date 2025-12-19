module ForestAdminDatasourceCustomizer
  module Decorators
    module RenameCollection
      class RenameCollectionDatasourceDecorator < ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator
        include ForestAdminDatasourceToolkit
        include ForestAdminDatasourceToolkit::Decorators
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

        def initialize(child_datasource)
          @from_child_name = {}
          @to_child_name = {}
          super(child_datasource, RenameCollectionDecorator)
        end

        def collections
          @child_datasource.collections.to_h do |name, _collection|
            [get_collection_name(name), method(:get_collection).super_method.call(name)]
          end
        end

        def get_collection(name)
          # Collection has been renamed, user is using the new name
          return super(@to_child_name[name]) if @to_child_name.key?(name)

          # Collection has been renamed, user is using the old name
          if @from_child_name.key?(name)
            raise Exceptions::ForestException, "Collection '#{name}' has been renamed to '#{@from_child_name[name]}'"
          end

          # Collection has not been renamed
          super
        end

        def rename_collections(renames)
          case renames
          when Proc
            collections.each_key do |name|
              rename_collection(name, renames.call(name) || name)
            end
          when Hash
            renames.each do |old_name, new_name|
              rename_collection(old_name, new_name)
            end
          else
            raise Exceptions::ForestException, 'Invalid argument for rename_collections, must be a function or a hash'
          end
        end

        def rename_collection(current_name, new_name)
          # Check collection exists
          get_collection(current_name)

          return unless current_name != new_name

          # Check new name is not already used
          if collections.any? { |name, _collection| name == new_name }
            raise Exceptions::ForestException,
                  "The given new collection name '#{new_name}' is already defined"
          end

          # Check we don't rename a collection twice
          if @to_child_name[current_name]
            raise Exceptions::ForestException,
                  "Cannot rename a collection twice: #{@to_child_name[current_name]}->#{current_name}->#{new_name}"
          end

          polymorphic_relations = %w[PolymorphicOneToOne PolymorphicOneToMany]
          collection.schema[:fields].each do |field_name, field_schema|
            next unless polymorphic_relations.include?(field_schema.type)

            reverse_relation_name = Utils::Collection.get_inverse_relation(collection, field_name)

            raise Exceptions::ForestException,
                  "Cannot rename collection #{current_name} because it's a target of a polymorphic relation " \
                  "'#{field_schema.foreign_collection}.#{reverse_relation_name}'"
          end

          @from_child_name[current_name] = new_name
          @to_child_name[new_name] = current_name

          collections.each_value(&:mark_schema_as_dirty)
        end

        def get_collection_name(child_name)
          @from_child_name[child_name] || child_name
        end

        # Get the Ruby class name for a collection (for polymorphic relations)
        # Returns demodulized name because ActiveRecord's polymorphic_class_for adds namespace prefixes
        def get_class_name_for_polymorphic(collection_name)
          original_name = @to_child_name[collection_name] || collection_name
          full_class_name = original_name.gsub('__', '::')
          full_class_name.split('::').last
        end
      end
    end
  end
end
