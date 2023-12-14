module ForestAdminDatasourceToolkit
  module Utils
    class Schema
      def self.foreign_key?(collection, name)
        field = collection.schema[:fields][name]

        field.type == 'Column' &&
          collection.schema[:fields].any? do |_key, relation|
            relation.type == 'ManyToOne' && relation.foreign_key == name
          end
      end

      def self.primary_key?(collection, name)
        field = collection.schema[:fields][name]

        field.type == 'Column' && field.is_primary_key
      end

      def self.primary_keys(collection)
        collection.schema[:fields].keys.select do |field_name|
          field = collection.schema[:fields][field_name]
          field.type == 'Column' && field.is_primary_key
        end
      end

      def self.get_to_many_relation(collection, relation_name)
        unless collection.schema[:fields].key?(relation_name)
          raise Exceptions::ForestException, "Relation #{relation_name} not found"
        end

        relation = collection.schema[:fields][relation_name]

        if relation.type != 'OneToMany' && relation.type != 'ManyToMany'
          raise Exceptions::ForestException,
                "Relation #{relation_name} has invalid type should be one of OneToMany or ManyToMany."
        end

        relation
      end
    end
  end
end
