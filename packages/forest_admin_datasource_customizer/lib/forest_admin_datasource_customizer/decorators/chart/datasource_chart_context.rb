module ForestAdminDatasourceCustomizer
  module Decorators
    module Chart
      class DatasourceChartContext < ForestAdminDatasourceCustomizer::Context::AgentCustomizationContext
        attr_reader :parameters

        def initialize(datasource, caller, parameters = {})
          super(datasource, caller)
          @parameters = (parameters || {}).freeze
        end
      end
    end
  end
end
