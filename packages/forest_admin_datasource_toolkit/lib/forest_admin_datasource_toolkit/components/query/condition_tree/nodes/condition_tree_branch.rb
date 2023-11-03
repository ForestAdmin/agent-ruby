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

            def match(record, collection, timezone)
              if @aggregator == 'And'
                every_leaf { |condition| condition.match(record, collection, timezone) }
              else
                some_leaf { |condition| condition.match(record, collection, timezone) }
              end
            end

            def for_each_leaf(&handler)
              @conditions.each { |condition| condition.for_each_leaf(&handler) }
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
