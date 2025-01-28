module ForestAdminDatasourceMongoid
  module Utils
    MongoidSerializer = Struct.new(:object) do
      def to_hash(projection)
        hash_object(object, projection)
      end

      def hash_object(object, projection, with_associations: true)
        hash = {}

        return if object.nil?

        object.attributes.slice(*projection.columns).each do |key, value|
          hash[key] = value
        end

        if with_associations
          each_association_collection(object, projection) do |association_name, item|
            hash[association_name] = hash_object(
              item,
              projection.relations[association_name],
              with_associations: projection.relations.key?(association_name)
            )
          end
        end

        hash
      end

      def each_association_collection(object, projection)
        one_associations = [Mongoid::Association::Referenced::HasOne, Mongoid::Association::Referenced::BelongsTo]
        object.class.reflect_on_all_associations
              .filter { |a| one_associations.include?(a.class) && projection.relations.key?(a.name.to_s) }
              .each { |association| yield(association.name.to_s, object.send(association.name.to_s)) }
      end
    end
  end
end
