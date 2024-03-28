module ForestAdminDatasourceCustomizer
  module Decorators
    module Chart
      class ChartCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit
        include ForestAdminDatasourceToolkit::Decorators

        attr_reader :charts

        def initialize(child_collection, datasource)
          @charts = {}
          super
        end

        def add_chart(name, &definition)
          raise(Exceptions::ForestException, "Chart #{name} already exists.") if schema[:charts].include?(name)

          @charts[name] = definition
          mark_schema_as_dirty
        end

        def render_chart(caller, name, record_id)
          if @charts.key?(name)
            context = ChartContext.new(self, caller, record_id)
            result_builder = ResultBuilder.new

            return @charts[name].call(context, result_builder)
          end

          @child_collection.render_chart(caller, name, record_id)
        end

        def refine_schema(sub_schema)
          sub_schema[:charts] = sub_schema[:charts] + @charts.keys

          sub_schema
        end
      end
    end
  end
end
