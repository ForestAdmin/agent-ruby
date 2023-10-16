module ForestAdminDatasourceToolkit
  module Utils
    class Record
      def self.primary_keys(collection, record)
        Schema.primary_keys(collection).map do |pk|
          record[pk] || raise(ForestException, "Missing primary key: #{pk}")
        end
      end

      def self.field_value(record, field)
        if field.include?(':')
          record = record.flatten
          field = field.tr(':', '.')
        end

        record[field]
      end
    end
  end
end
