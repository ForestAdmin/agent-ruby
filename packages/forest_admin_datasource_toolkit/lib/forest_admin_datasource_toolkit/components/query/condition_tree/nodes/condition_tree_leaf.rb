module ForestAdminDatasourceToolkit
  module Components
    module Query
      module ConditionTree
        module Nodes
          class ConditionTreeLeaf < ConditionTree
            include ForestAdminDatasourceToolkit::Utils
            include ForestAdminDatasourceToolkit::Exceptions

            attr_reader :field, :operator, :value

            def initialize(field, operator, value = nil)
              @field = field
              @operator = operator
              @value = value
              valid_operator(@operator) if @operator
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
              return if Operators.all_operators.include?(value.upcase.to_sym)

              raise ForestException, "Invalid operators, the #{value} operator does not exist."
            end

            def inverse
              if Operators.all_operators.include?("Not_#{@operator}".upcase.to_sym)
                return override(operator: "Not_#{@operator}")
              end
              return override(operator: @operator[4..]) if @operator.start_with?('Not')

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

            def match(record, collection, timezone)
              field_value = Record.field_value(record, @field)
              column_type = ForestAdminDatasourceToolkit::Utils::Collection.get_field_schema(collection,
                                                                                             @field).column_type
              supported = %w[In Equal LessThan GreaterThan Match StartsWith EndsWith LongerThan ShorterThan IncludesAll
                             NotIn NotEqual NotContains]

              case @operator
              when 'In'
                Array(@value).include?(field_value)
              when 'Equal'
                field_value == @value
              when 'LessThan'
                field_value < @value
              when 'GreaterThan'
                field_value > @value
              when 'Match'
                field_value.is_a?(String) && field_value.match(@value)
              when 'StartsWith'
                field_value.is_a?(String) && field_value.start_with?(@value)
              when 'EndsWith'
                field_value.is_a?(String) && field_value.end_with?(@value)
              when 'LongerThan'
                field_value.is_a?(String) && field_value.length > @value
              when 'ShorterThan'
                field_value.is_a?(String) && field_value.length < @value
              when 'IncludesAll'
                Array(@value).all? { |v| field_value.include?(v) }
              when 'NotIn', 'NotEqual', 'NotContains'
                !inverse.match(record, collection, timezone)
              else
                ConditionTreeEquivalent.get_equivalent_tree(
                  self,
                  supported,
                  column_type,
                  timezone
                )&.match(record, collection, timezone)
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

            def override(args)
              ConditionTreeLeaf.new(
                args[:field] || @field,
                args[:operator] || @operator,
                args[:value] || @value
              )
            end

            def use_interval_operator
              Operators.interval_operators.include?(@operator)
            end
          end
        end
      end
    end
  end
end
