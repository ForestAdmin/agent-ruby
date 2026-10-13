module ForestAdminDatasourceActiveRecord
  module Utils
    # Relations in `joined_relations` (see Query#collect_joined_selects) are hydrated from the flat
    # row's aliased columns; every other relation is read from its preloaded ActiveRecord association.
    # One instance serializes every record of a list, so the projection tree and reflections are resolved once.
    class ActiveRecordSerializer
      ONE_ASSOCIATIONS = %i[has_one belongs_to].freeze
      MANY_ASSOCIATIONS = %i[has_many has_and_belongs_to_many].freeze

      def initialize(projection, joined_relations = nil)
        @tree = ForestAdminDatasourceToolkit::Components::Query::ProjectionTree.build(projection)
        @joined_relations = joined_relations || {}
        @join_aliases = @joined_relations.values.flat_map { |meta| meta[:columns].values }.uniq
        @polymorphic_belongs_to = {}
        @target_models = {}
      end

      def serialize(object)
        hash_object(object, object, @tree)
      end

      # Target model of a JOINed relation path (only belongs_to / has_one :through are ever JOINed).
      def target_model(root_model, relation_path)
        @target_models.fetch([root_model, relation_path]) do |key|
          @target_models[key] = resolve_target_model(root_model, relation_path)
        end
      end

      private

      def hash_object(root, object, tree, path: [])
        return if object.nil?

        # root keeps all its selected columns (attributes + FKs); a related record is restricted to
        # its projected columns, matching the JOINed hydration
        hash = path.empty? ? base_attributes(object) : projected_columns(object, tree)
        hash = normalize_polymorphic_types(object.class, hash)

        serialize_associations(root, object, tree, hash, path)

        hash
      end

      def base_attributes(object)
        return object.attributes if @join_aliases.empty?

        object.attributes.except(*@join_aliases)
      end

      def projected_columns(object, tree)
        tree.columns.to_h { |column| [column, object[column]] }
      end

      def serialize_associations(root, object, tree, hash, path)
        tree.relations.each do |association_name, sub_tree|
          relation_path = path + [association_name]

          if @joined_relations.key?(relation_path.join('.'))
            hash[association_name] = hash_joined_relation(root, sub_tree, relation_path)
            next
          end

          association = object.class.reflect_on_association(association_name.to_sym)
          next if association.nil?

          if ONE_ASSOCIATIONS.include?(association.macro)
            hash[association_name] = hash_object(root, object.send(association_name), sub_tree, path: relation_path)
          elsif MANY_ASSOCIATIONS.include?(association.macro)
            hash[association_name] = object.send(association_name).map do |item|
              hash_object(root, item, sub_tree, path: relation_path)
            end
          end
        end
      end

      # Reads a JOINed relation's columns from the aliases on the root object (not a nested one).
      def hash_joined_relation(root, tree, relation_path)
        meta = @joined_relations[relation_path.join('.')]
        return nil if root[meta[:pk_alias]].nil?

        hash = {}
        tree.columns.each { |column| hash[column] = root[meta[:columns][column]] }
        hash = normalize_polymorphic_types(target_model(root.class, relation_path), hash)
        tree.relations.each do |nested_name, nested_tree|
          hash[nested_name] = hash_joined_relation(root, nested_tree, relation_path + [nested_name])
        end

        hash
      end

      def normalize_polymorphic_types(model_class, hash)
        return hash if model_class.nil?

        polymorphic_belongs_to(model_class).each do |association|
          stored = hash[association.foreign_type]
          next if stored.nil?

          hash = hash.merge(association.foreign_type => model_class.polymorphic_class_for(stored).name)
        rescue NameError => e
          warn_unable(association.name, model_class, e)
        end
        hash
      end

      def resolve_target_model(root_model, relation_path)
        relation_path.reduce(root_model) do |model, name|
          model&.reflect_on_association(name.to_sym)&.klass
        end
      rescue NameError
        nil
      end

      def polymorphic_belongs_to(model_class)
        @polymorphic_belongs_to[model_class] ||=
          model_class.reflect_on_all_associations(:belongs_to).select(&:polymorphic?)
      end

      def warn_unable(name, model_class, error)
        ActiveSupport::Logger.new($stdout).warn(
          "[ForestAdmin] Unable to normalize polymorphic type of '#{name}' " \
          "in model '#{model_class.name}': #{error.message}. Keeping the stored value."
        )
      end
    end
  end
end
