module ForestAdminDatasourceToolkit
  module Validations
    class ProjectionValidator
      def self.validate?(collection, projection)
        projection.each { |field| FieldValidator.validate(collection, field) }
      end
    end
  end
end
