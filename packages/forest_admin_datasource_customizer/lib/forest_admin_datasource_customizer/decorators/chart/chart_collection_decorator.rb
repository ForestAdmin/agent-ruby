module ForestAdminDatasourceCustomizer
  module Decorators
    module Chart
      class ChartCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Decorators
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      end
    end
  end
end
