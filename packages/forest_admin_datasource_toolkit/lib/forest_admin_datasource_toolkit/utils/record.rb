module ForestAdminDatasourceToolkit
  module Utils
    class Record
      def self.primary_keys(collection, record)
        Schema.primary_keys(collection).map do |pk|
          record[pk] || raise(ForestAdminDatasourceToolkit::Exceptions::ForestException, "Missing primary key: #{pk}")
        end
      end

      def self.field_value(record, field)
        path = field.split(':')
        current = record

        current = current[path.shift.to_sym] while path.length.positive? && current

        path.empty? ? current : nil
      end
    end
  end
end
