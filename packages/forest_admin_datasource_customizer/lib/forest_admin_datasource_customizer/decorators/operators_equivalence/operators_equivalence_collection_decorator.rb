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

        def refine_filter(caller, filter = nil)
          filter&.override(
            condition_tree: filter.condition_tree&.replace_leafs do |leaf|
              schema = ForestAdminDatasourceToolkit::Utils::Collection.get_field_schema(
                @child_collection,
                leaf.field
              )

              ConditionTreeEquivalent.get_equivalent_tree(
                leaf,
                schema.filter_operators,
                schema.column_type,
                caller.timezone
              )
            end
          )
        end
      end
    end
  end
end
