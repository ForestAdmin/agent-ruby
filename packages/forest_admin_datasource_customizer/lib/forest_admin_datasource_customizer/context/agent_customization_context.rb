module ForestAdminDatasourceCustomizer
  module Context
    class AgentCustomizationContext
      include ForestAdminDatasourceCustomizer::Context::RelaxedWrappers

      attr_reader :caller

      def initialize(datasource, caller)
        @real_datasource = datasource
        @caller = caller
      end

      def datasource
        RelaxedDataSource.new(@real_datasource, @caller)
      end
    end
  end
end
