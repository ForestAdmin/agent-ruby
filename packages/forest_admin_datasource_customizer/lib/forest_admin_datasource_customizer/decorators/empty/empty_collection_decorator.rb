module ForestAdminDatasourceCustomizer
  module Decorators
    module Empty
      class EmptyCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Decorators
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

        def list(_caller, filter, _projection)
          return super unless return_empty_set(filter.condition_tree)

          []
        end

        def update(caller, filter, patch)
          super unless return_empty_set(filter.condition_tree)
        end

        def delete(caller, filter)
          super unless return_empty_set(filter.condition_tree)
        end

        def aggregate(caller, filter, aggregation, limit = nil)
          return super unless return_empty_set(filter.condition_tree)

          []
        end

        private

        def return_empty_set(tree)
          return leaf_return_empty_set(tree) if tree.is_a? Nodes::ConditionTreeLeaf

          if tree.is_a?(Nodes::ConditionTreeBranch) && tree.aggregator == 'Or'
            return or_return_empty_set(tree.conditions)
          end

          if tree.is_a?(Nodes::ConditionTreeBranch) && tree.aggregator == 'And'
            return and_return_empty_set(tree.conditions)
          end

          false
        end

        def leaf_return_empty_set(leaf)
          # Empty 'in` always return zero records.
          leaf.operator == Operators::IN && leaf.value.empty?
        end

        def or_return_empty_set(conditions)
          # Or return no records when
          # - they have no conditions
          # - they have only conditions which return zero records.
          conditions.empty? || conditions.all? { |condition| return_empty_set(condition) }
        end

        def and_return_empty_set(conditions)
          # There is a leaf which returns zero records
          return true if conditions.one? { |condition| return_empty_set(condition) }

          # Scans for mutually exclusive conditions
          # (this a naive implementation, it will miss many occurrences)
          values_by_field = {}
          leafs = conditions.select { |condition| condition.is_a? Nodes::ConditionTreeLeaf }
          leafs.each do |leaf|
            field, operator, value = leaf.to_h.values_at(:field, :operator, :value)
            if !values_by_field.key?(field) && operator == Operators::EQUAL
              values_by_field[field] = [value]
            elsif !values_by_field.key?(field) && operator == Operators::IN
              values_by_field[field] = value
            elsif values_by_field.key?(field) && operator == Operators::EQUAL
              values_by_field[field] = values_by_field[field].include?(value) ? [value] : []
            elsif values_by_field.key?(field) && operator == Operators::IN
              values_by_field[field] = values_by_field[field].select { |v| value.include?(v) }
            end
          end

          values_by_field.values.one?(&:empty?)
        end
      end
    end
  end
end
