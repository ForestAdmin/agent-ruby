module ForestAdminDatasourceToolkit
  module Utils
    class HashHelper
      def self.convert_keys(object, method = :to_sym)
        if object.is_a? Array
          object.each_with_object([]) do |value, new_array|
            new_array << convert_keys(value, method)
          end
        elsif object.is_a? Hash
          object.each_with_object({}) do |(key, value), new_hash|
            new_hash[key.send(method)] = value.is_a?(Hash) ? convert_keys(value, method) : value
          end
        else
          object
        end
      end
    end
  end
end
