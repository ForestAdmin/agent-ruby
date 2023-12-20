module ForestAdminDatasourceCustomizer
  module Context
    class CollectionCustomizationContext < AgentCustomizationContext
      def initialize(collection, caller)
        super(collection.datasource, caller)
        @real_collection = collection
      end

      def collection
        RelaxedCollection.new(@real_collection, @caller)
      end
    end
  end
end
