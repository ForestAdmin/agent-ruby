module ForestAdminDatasourceToolkit
  module Query
    module ConditionTree
      module Nodes
        class ConditionTreeLeaf < ConditionTree
          include ForestAdminDatasourceToolkit::Utils

          attr_reader :field, :operator, :value

          def initialize(field, operator, value = nil)
            @field = field
            @operator = operator
            @value = value
            @operator&.valid_operator(@operator)
            super()
          end

          def to_h
            {
              field: @field,
              operator: @operator,
              value: @value
            }
          end

          def valid_operator(value)
            return if Operators.all_operators.include?(value)

            raise ForestException, "Invalid operators, the #{value} operator does not exist."
          end

          def inverse
            override(operator: "Not_#{@operator}") if Operators.all_operators.include?("Not_#{@operator}")
            override(operator: @operator[4..]) if @operator.start_with?('Not')

            case @operator
            when 'Blank'
              override(operator: 'Present')
            when 'Present'
              override(operator: 'Blank')
            else
              raise ForestException, "Operator: #{@operator} cannot be inverted."
            end
          end

          def replace_leafs
            result = yield(self)
            if result.nil?
              nil
            elsif result.is_a?(ConditionTree)
              result
            else
              ConditionTreeFactory.from_array(result)
            end
          end

          def for_each_leaf
            yield(self)
          end

          def every_leaf
            yield(self)
          end

          def some_leaf
            yield(self)
          end

          def projection
            Projection.new([@field])
          end

          def override(*args)
            ConditionTreeLeaf.new(*to_a.concat(args))
          end

          def use_interval_operator
            Operators.interval_operators.include?(@operator)
          end
        end
      end
    end
  end
end
