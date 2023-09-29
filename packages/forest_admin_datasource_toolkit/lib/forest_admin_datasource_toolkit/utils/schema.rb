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
    end
  end
end
