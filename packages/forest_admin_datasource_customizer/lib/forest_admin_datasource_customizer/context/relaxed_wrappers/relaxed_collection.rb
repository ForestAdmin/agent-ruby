module ForestAdminDatasourceCustomizer
  module Context
    module RelaxedWrappers
      class RelaxedCollection
        def initialize(collection, caller)
          @collection = collection
          @caller = caller
        end
      end
    end
  end
end
