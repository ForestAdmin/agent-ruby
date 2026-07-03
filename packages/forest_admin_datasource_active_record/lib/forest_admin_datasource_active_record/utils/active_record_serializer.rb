module ForestAdminDatasourceActiveRecord
  module Utils
    # Relations in `joined_relations` (see Query#collect_joined_selects) are hydrated from the flat
    # row's aliased columns; every other relation is read from its preloaded ActiveRecord association.
    ActiveRecordSerializer = Struct.new(:object, :joined_relations) do
      def to_hash(projection)
        hash_object(object, projection)
      end

      def hash_object(object, projection = nil, path: [])
        return if object.nil?

        # root keeps all its selected columns (attributes + FKs); a related record is restricted to
        # its projected columns, matching the JOINed hydration
        hash = path.empty? || projection.nil? ? base_attributes(object) : projected_columns(object, projection)
        hash = normalize_polymorphic_types(object.class, hash)

        serialize_associations(object, projection, hash, path) if projection

        hash
      end

      def base_attributes(object)
        return object.attributes if join_aliases.empty?

        object.attributes.except(*join_aliases)
      end

      def projected_columns(object, projection)
        projection.columns.to_h { |column| [column, object[column]] }
      end

      def serialize_associations(object, projection, hash, path)
        one_associations = %i[has_one belongs_to]
        many_associations = %i[has_many has_and_belongs_to_many]

        projection.relations.each_key do |association_name|
          relation_path = path + [association_name]

          if joined_relation?(relation_path)
            hash[association_name] = hash_joined_relation(projection.relations[association_name], relation_path)
            next
          end

          association = object.class.reflect_on_association(association_name.to_sym)
          next if association.nil?

          if one_associations.include?(association.macro)
            hash[association_name] = hash_object(
              object.send(association_name),
              projection.relations[association_name],
              path: relation_path
            )
          elsif many_associations.include?(association.macro)
            hash[association_name] = object.send(association_name).map do |item|
              hash_object(item, projection.relations[association_name], path: relation_path)
            end
          end
        end
      end

      # Reads a JOINed relation's columns from the aliases on the root object (not a nested one).
      def hash_joined_relation(projection, relation_path)
        meta = joined_relations[relation_path.join('.')]
        return nil if object[meta[:pk_alias]].nil?

        hash = {}
        projection.columns.each { |column| hash[column] = object[meta[:columns][column]] }
        hash = normalize_polymorphic_types(target_model(relation_path), hash)
        projection.relations.each_key do |nested_name|
          hash[nested_name] = hash_joined_relation(projection.relations[nested_name], relation_path + [nested_name])
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

      # Target model of a JOINed relation path (only belongs_to / has_one :through are ever JOINed).
      def target_model(relation_path)
        relation_path.reduce(object.class) do |model, name|
          model&.reflect_on_association(name.to_sym)&.klass
        end
      rescue NameError
        nil
      end

      private

      def polymorphic_belongs_to(model_class)
        (@polymorphic_belongs_to ||= {})[model_class] ||=
          model_class.reflect_on_all_associations(:belongs_to).select(&:polymorphic?)
      end

      def warn_unable(name, model_class, error)
        ActiveSupport::Logger.new($stdout).warn(
          "[ForestAdmin] Unable to normalize polymorphic type of '#{name}' " \
          "in model '#{model_class.name}': #{error.message}. Keeping the stored value."
        )
      end

      def joined_relation?(relation_path)
        !joined_relations.nil? && joined_relations.key?(relation_path.join('.'))
      end

      def join_aliases
        @join_aliases ||= (joined_relations || {}).values.flat_map { |meta| meta[:columns].values }.uniq
      end
    end
  end
end
