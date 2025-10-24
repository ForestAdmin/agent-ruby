module ForestAdminDatasourceToolkit
  module Validations
    class RecordValidator
      include ForestAdminAgent::Http::Exceptions

      def self.validate(collection, record_data)
        if !record_data || record_data.empty?
          raise ForestAdminAgent::Http::Exceptions::BadRequestError,
                'The record data is empty'
        end

        record_data.each_key do |key|
          schema = collection.schema[:fields][key]

          if !schema
            raise ForestAdminAgent::Http::Exceptions::NotFoundError, "Unknown field #{key}"
          elsif schema.type == 'Column'
            FieldValidator.validate(collection, key, record_data[key])
          elsif ['OneToOne', 'ManyToOne'].include?(schema.type)
            sub_record = record_data[key]
            association = collection.datasource.get_collection(schema.foreign_collection)
            RecordValidator.validate(association, sub_record)
          else
            raise ForestAdminAgent::Http::Exceptions::UnprocessableError,
                  "Unexpected schema type '#{schema.type}' while traversing record"
          end
        end
      end
    end
  end
end
