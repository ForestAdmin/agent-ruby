module ForestAdminDatasourceToolkit
  module Components
    module Query
      module ConditionTree
        module Nodes
          class ConditionTreeBranch < ConditionTree
            attr_reader :aggregator, :conditions

            def initialize(aggregator, conditions)
              @aggregator = aggregator
              @conditions = conditions
              super()
            end

            def to_h
              {
                aggregator: @aggregator,
                conditions: @conditions.map(&:to_h)
              }
            end

            def inverse
              aggregator = @aggregator == 'Or' ? 'And' : 'Or'
              ConditionTreeBranch.new(
                aggregator,
                @conditions.map(&:inverse)
              )
            end

            def replace_leafs(&handler)
              ConditionTreeBranch.new(
                @aggregator,
                @conditions.map { |condition| condition.replace_leafs(&handler) }
              )
            end

            # Recurses through `match`, not through `every_leaf` / `some_leaf`:
            # those walk down to the leaves and would apply this branch's
            # aggregator to a nested one's, reading `And(a, Or(b, c))` as
            # `And(a, b, c)`.
            def match(record, collection, timezone)
              if @aggregator == 'And'
                @conditions.all? { |condition| condition.match(record, collection, timezone) }
              else
                @conditions.any? { |condition| condition.match(record, collection, timezone) }
              end
            end

            def for_each_leaf(&handler)
              @conditions.map! { |condition| condition.for_each_leaf(&handler) }
              self
            end

            def every_leaf(&handler)
              @conditions.all? { |condition| condition.every_leaf(&handler) }
            end

            def some_leaf(&handler)
              @conditions.any? { |condition| condition.some_leaf(&handler) }
            end

            def projection
              @conditions.reduce(Projection.new) do |memo, condition|
                memo.union(condition.projection)
              end
            end
          end
        end
      end
    end
  end
end
