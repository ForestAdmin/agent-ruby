module ForestAdminDatasourceCustomizer
  module Decorators
    module Chart
      class ChartContext < ForestAdminDatasourceCustomizer::Context::CollectionCustomizationContext
        include ForestAdminDatasourceToolkit
        include ForestAdminDatasourceToolkit::Components::Query
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

        def initialize(collection, caller, record_id)
          super(collection, caller)
          @composite_record_id = record_id
        end

        def record_id
          if @composite_record_id.size > 1
            raise Exceptions::ForestException,
                  "Collection is using a composite pk: use 'context.composite_record_id'."
          end

          @composite_record_id[0]
        end

        def get_record(fields)
          condition_tree = ConditionTreeFactory.match_ids(@real_collection, [@composite_record_id])

          collection.list(Filter.new(condition_tree: condition_tree), Projection.new(fields))[0]
        end
      end
    end
  end
end
