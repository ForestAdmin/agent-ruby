module ForestAdminDatasourceCustomizer
  module Decorators
    module OperatorsEquivalence
      class OperatorsEquivalenceCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Decorators
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

        protected

        def refine_schema(sub_schema)
          sub_schema[:fields].map do |_name, schema|
            if schema.type == 'Column'
              new_operators = Operators.all.select do |operator|
                ConditionTreeEquivalent.equivalent_tree?(operator, schema.filter_operators, schema.column_type)
              end

              schema.filter_operators = new_operators
            else
              schema
            end
          end

          sub_schema
        end
      end
    end
  end
end
