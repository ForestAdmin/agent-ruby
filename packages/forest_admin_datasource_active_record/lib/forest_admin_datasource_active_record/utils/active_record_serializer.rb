module ForestAdminDatasourceActiveRecord
  module Utils
    ActiveRecordSerializer = Struct.new(:object) do
      def to_hash(projection)
        hash_object(object, projection)
      end

      def hash_object(object, projection = nil, with_associations: true)
        hash = {}

        return if object.nil?

        hash.merge! object.attributes

        serialize_associations(object, projection, hash) if with_associations

        hash
      end

      def serialize_associations(object, projection, hash)
        one_associations = %i[has_one belongs_to]
        many_associations = %i[has_many has_and_belongs_to_many]

        # Handle one-to-one and many-to-one associations
        object.class.reflect_on_all_associations
              .filter { |a| one_associations.include?(a.macro) && projection.relations.key?(a.name.to_s) }
              .each do |association|
                association_name = association.name.to_s
                hash[association_name] = hash_object(
                  object.send(association_name),
                  projection.relations[association_name],
                  with_associations: projection.relations.key?(association_name)
                )
              end

        # Handle one-to-many and many-to-many associations
        object.class.reflect_on_all_associations
              .filter { |a| many_associations.include?(a.macro) && projection.relations.key?(a.name.to_s) }
              .each do |association|
                association_name = association.name.to_s
                collection = object.send(association_name)
                # Serialize the collection as an array
                hash[association_name] = collection.map do |item|
                  hash_object(
                    item,
                    projection.relations[association_name],
                    with_associations: projection.relations.key?(association_name)
                  )
                end
              end
      end
    end
  end
end
