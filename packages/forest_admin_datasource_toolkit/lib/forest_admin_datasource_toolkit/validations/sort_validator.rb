module ForestAdminDatasourceToolkit
  module Validations
    class SortValidator
      def self.validate(collection, sort)
        sort&.each do |s|
          FieldValidator.validate(collection, s[:field])
          unless s[:ascending].is_a?(TrueClass) || s[:ascending].is_a?(FalseClass)
            raise ForestAdminDatasourceToolkit::Exceptions::ValidationError,
                  "Invalid sort_utils.ascending value: #{s[:ascending]}"
          end
        end
      end
    end
  end
end
