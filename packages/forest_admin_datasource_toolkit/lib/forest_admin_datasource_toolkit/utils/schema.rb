module ForestAdminDatasourceToolkit
  module Utils
    class Schema
      def self.foreign_key?(collection, name)
        field = collection.fields[name]

        field.type == 'Column' &&
          collection.fields.any? do |_key, relation|
            relation.type == 'ManyToOne' && relation.foreign_key == name
          end
      end

      def self.primary_key?(collection, name)
        field = collection.fields[name]

        field.type == 'Column' && field.is_primary_key
      end

      def self.primary_keys(collection)
        collection.fields.keys.select do |field_name|
          field = collection.fields[field_name]
          field.type == 'Column' && field.is_primary_key
        end
      end
    end
  end
end
