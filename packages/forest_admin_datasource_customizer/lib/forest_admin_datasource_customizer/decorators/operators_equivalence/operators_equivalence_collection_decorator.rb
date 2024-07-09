module ForestAdminDatasourceCustomizer
  module Decorators
    module OperatorsEquivalence
      class OperatorsEquivalenceCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Decorators
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

        protected

        def refine_schema(sub_schema)
          schema = sub_schema.dup
          schema[:fields] = sub_schema[:fields].dup

          schema[:fields].map do |_name, field_schema|
            field_schema = field_schema.dup
            if field_schema.type == 'Column'
              new_operators = Operators.all.select do |operator|
                ConditionTreeEquivalent.equivalent_tree?(operator, field_schema.filter_operators,
                                                         field_schema.column_type)
              end

              field_schema.filter_operators = new_operators
            else
              field_schema
            end
          end

          schema
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
