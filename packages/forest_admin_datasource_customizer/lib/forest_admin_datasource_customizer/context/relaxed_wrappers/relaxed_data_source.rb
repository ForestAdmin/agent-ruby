module ForestAdminDatasourceCustomizer
  module Context
    module RelaxedWrappers
      class RelaxedDataSource
        def initialize(datasource, caller)
          @real_datasource = datasource
          @caller = caller
        end

        # Get a collection from a datasource
        # @param name the name of the collection
        def get_collection(name)
          RelaxedCollection.new(@real_datasource.get_collection(name), @caller)
        end
      end
    end
  end
end
