module ForestAdminDatasourceCustomizer
  module Decorators
    module Chart
      class ChartDatasourceDecorator < ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator
        include ForestAdminDatasourceToolkit
        include ForestAdminDatasourceToolkit::Decorators

        def initialize(child_datasource)
          @charts = {}
          super(child_datasource, ChartCollectionDecorator)
        end

        def schema
          child_schema = @child_datasource.schema.dup

          duplicate = @charts.keys.find { |name| child_schema[:charts].include?(name) }

          raise ForestAdminAgent::Http::Exceptions::ConflictError, "Chart #{duplicate} is defined twice." if duplicate

          child_schema[:charts] = child_schema[:charts].union(@charts.keys)

          child_schema
        end

        def add_chart(name, &definition)
          if schema[:charts].include?(name)
            raise ForestAdminAgent::Http::Exceptions::ConflictError, "Chart #{name} already exists."
          end

          @charts[name] = definition
        end

        def render_chart(caller, name)
          chart_definition = @charts[name]

          if chart_definition
            return chart_definition.call(
              Context::AgentCustomizationContext.new(self, caller),
              ResultBuilder.new
            )
          end

          super
        end
      end
    end
  end
end
