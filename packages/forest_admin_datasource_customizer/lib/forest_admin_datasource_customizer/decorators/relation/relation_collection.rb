module ForestAdminDatasourceCustomizer
  module Decorators
    module Relation
      class RelationCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Utils
        include ForestAdminDatasourceToolkit::Components::Query
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes

        def initialize(child_collection, datasource)
          super
          @relations = {}
        end

        def add_relation(name, partial_joint); end
      end
    end
  end
end
