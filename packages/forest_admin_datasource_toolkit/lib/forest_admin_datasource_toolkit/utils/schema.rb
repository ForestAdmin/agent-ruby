module ForestAdminDatasourceToolkit
  module Utils
    class Schema
      def self.foreign_key?(collection, name)
        field = collection.fields[name]

        field.type == 'Column' &&
          collection.fields.any? do |_name, relation|
            relation.type == 'ManyToOne' && relation.foreign_key == name
          end
      end
    end
  end
end
