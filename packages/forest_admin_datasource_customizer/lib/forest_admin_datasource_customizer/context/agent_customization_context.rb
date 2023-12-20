module ForestAdminDatasourceCustomizer
  module Context
    class AgentCustomizationContext
      def initialize(datasource, caller)
        @real_datasource = datasource
        @caller = caller
      end

      def datasource
        RelaxedDataSource.new(@real_datasource, @caller)
      end

      #   get caller() {
      #     return Object.freeze(this._caller);
      #   }
    end
  end
end
