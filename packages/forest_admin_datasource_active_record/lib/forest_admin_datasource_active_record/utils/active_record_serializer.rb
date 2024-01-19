module ForestAdminDatasourceActiveRecord
  module Utils
    ActiveRecordSerializer = Struct.new(:object) do
      def to_hash
        hash_object(object)
      end

      def hash_object(object, with_associations: true)
        hash = {}

        return {} if object.nil?

        hash.merge! object.attributes

        if with_associations
          each_association_collection(object) do |association_name, item|
            hash[association_name] = hash_object(item, with_associations: false)
          end
        end

        hash
      end

      def each_association_collection(object)
        one_associations = %i[has_one belongs_to]
        object.class.reflect_on_all_associations.filter { |a| one_associations.include?(a.macro) }
              .each { |association| yield(association.name.to_s, object.send(association.name.to_s)) }
      end
    end
  end
end
