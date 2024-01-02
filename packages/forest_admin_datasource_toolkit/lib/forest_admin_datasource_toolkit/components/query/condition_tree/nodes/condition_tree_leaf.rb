require 'active_support'
require 'active_support/core_ext/string'

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
              @operator = operator.underscore
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
              return if Operators.exist?(value)

              raise ForestException, "Invalid operators, the #{value} operator does not exist."
            end

            def inverse
              return override(operator: "not_#{@operator}") if Operators.exist?("not_#{@operator}")
              return override(operator: @operator[4..]) if @operator.start_with?('not')

              case @operator
              when Operators::BLANK
                override(operator: Operators::BLANK)
              when Operators::PRESENT
                override(operator: Operators::PRESENT)
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
              column_type = Utils::Collection.get_field_schema(collection, @field).column_type

              supported = [
                Operators::IN,
                Operators::EQUAL,
                Operators::LESS_THAN,
                Operators::GREATER_THAN,
                Operators::MATCH,
                Operators::STARTS_WITH,
                Operators::ENDS_WITH,
                Operators::LONGER_THAN,
                Operators::SHORTER_THAN,
                Operators::INCLUDES_ALL,
                Operators::NOT_IN,
                Operators::NOT_EQUAL,
                Operators::NOT_CONTAINS
              ]

              case @operator
              when Operators::IN
                Array(@value).include?(field_value)
              when Operators::EQUAL
                field_value == @value
              when Operators::LESS_THAN
                field_value < @value
              when Operators::GREATER_THAN
                field_value > @value
              when Operators::MATCH
                field_value.is_a?(String) && @value.match(field_value)
              when Operators::STARTS_WITH
                field_value.is_a?(String) && field_value.start_with?(@value)
              when Operators::ENDS_WITH
                field_value.is_a?(String) && field_value.end_with?(@value)
              when Operators::LONGER_THAN
                field_value.is_a?(String) && field_value.length > @value
              when Operators::SHORTER_THAN
                field_value.is_a?(String) && field_value.length < @value
              when Operators::INCLUDES_ALL
                Array(@value).all? { |v| field_value.include?(v) }
              when Operators::NOT_IN, Operators::NOT_EQUAL, Operators::NOT_CONTAINS
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
