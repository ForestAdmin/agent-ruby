module ForestAdminDatasourceToolkit
  module Validations
    class RecordValidator
      include ForestAdminDatasourceToolkit::Exceptions

      def self.validate(collection, record_data)
        raise ForestException, 'The record data is empty' if !record_data || record_data.keys.empty?

        record_data.each_key do |key|
          schema = collection.schema[:fields][key]

          if !schema
            raise ForestException, "Unknown field #{key}"
          elsif schema[:type] == 'Column'
            FieldValidator.validate(collection, key, record_data[key])
          elsif schema[:type] == 'OneToOne' || schema[:type] == 'ManyToOne'
            sub_record = record_data[key]
            association = collection.datasource.get_collection(schema[:foreign_collection])
            RecordValidator.validate(association, sub_record)
          else
            raise ForestException, "Unexpected schema type '#{schema[:type]}' while traversing record"
          end
        end
      end
    end
  end
end
