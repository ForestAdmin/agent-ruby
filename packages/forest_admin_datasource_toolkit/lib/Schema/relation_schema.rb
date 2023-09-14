module ForestAdminDatasourceToolkit
  module Schema
    class RelationSchema
      self.abstract_class = true

      attr_accessor :foreign_collection
      attr_reader :type

      def initialize(foreign_collection, type)
        @foreign_collection = foreign_collection
        @type = type
      end
    end
  end
end
