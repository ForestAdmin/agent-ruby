module ForestAdminDatasourceToolkit
  module Schema
    class RelationSchema
      attr_accessor :foreign_collection
      attr_reader :type, :is_read_only

      def initialize(foreign_collection, type, is_read_only: false)
        @foreign_collection = foreign_collection
        @type = type
        @is_read_only = is_read_only
      end
    end
  end
end
