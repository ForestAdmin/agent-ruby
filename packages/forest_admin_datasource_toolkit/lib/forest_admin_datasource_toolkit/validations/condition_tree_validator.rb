module ForestAdminDatasourceToolkit
  module Validations
    class ConditionTreeValidator
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      def self.validate(condition_tree, collection)
        if condition_tree.is_a?(Nodes::ConditionTreeBranch)
          validate_branch(condition_tree, collection)
        elsif condition_tree.is_a?(Nodes::ConditionTreeLeaf)
          validate_leaf(condition_tree, collection)
        else
          raise Exceptions::ValidationError, 'Unexpected condition tree type'
        end
      end

      def self.validate_branch(branch, collection)
        unless %w[And Or].include?(branch.aggregator)
          raise Exceptions::ValidationError,
                "The given aggregator '#{branch.aggregator}' is not supported. The supported values are: ['Or', 'And']"
        end

        unless branch.conditions.is_a?(Array)
          raise Exceptions::ValidationError,
                "The given conditions '#{branch.conditions}' were expected to be an array"
        end

        branch.conditions.each { |condition| validate(condition, collection) }

        nil
      end

      def self.validate_leaf(leaf, collection)
        field_schema = Utils::Collection.get_field_schema(collection, leaf.field)

        throw_if_operator_not_allowed_with_column(leaf, field_schema)
        throw_if_value_not_allowed_with_operator(leaf, field_schema)
        throw_if_operator_not_allowed_with_column_type(leaf, field_schema)
        throw_if_value_not_allowed_with_column_type(leaf, field_schema)
      end

      def self.throw_if_operator_not_allowed_with_column(leaf, column_schema)
        operators = column_schema.filter_operators
        return if operators.include?(leaf.operator)

        raise Exceptions::ValidationError,
              "The given operator '#{leaf.operator}' is not supported by the column: '#{leaf.field}'." \
              "#{operators.empty? ? " The allowed types are: #{operators.join(",")}" : " The column is not filterable"}"
      end

      def self.throw_if_value_not_allowed_with_operator(leaf, column_schema)
        allowed_types = Rules.get_allowed_types_for_operator(leaf.operator)
        validate_values(leaf.field, column_schema, leaf.value, allowed_types)
      end

      def self.throw_if_operator_not_allowed_with_column_type(leaf, column_schema)
        allowed_operators = Rules.get_allowed_operators_for_column_type(column_schema.column_type)

        return if allowed_operators.include?(leaf.operator)

        raise Exceptions::ValidationError,
              "The given operator '#{leaf.operator}' is not allowed with the columnType schema: " \
              "'#{column_schema.column_type}'. The allowed types are: [#{allowed_operators.join(",")}]"
      end

      def self.throw_if_value_not_allowed_with_column_type(leaf, column_schema)
        # exclude some cases where the value is not related to the columnType of the field
        excluded_cases = [
          Operators::SHORTER_THAN,
          Operators::LONGER_THAN,
          Operators::AFTER_X_HOURS_AGO,
          Operators::BEFORE_X_HOURS_AGO,
          Operators::PREVIOUS_X_DAYS,
          Operators::PREVIOUS_X_DAYS_TO_DATE
        ]

        return if excluded_cases.include?(leaf.operator)

        types = Rules.get_allowed_types_for_column_type(column_schema.column_type)
        validate_values(leaf.field, column_schema, leaf.value, types)
      end

      def self.validate_values(field, column_schema, value, allowed_types)
        if value.is_a?(Array)
          value.each do |item|
            FieldValidator.validate_value(field, column_schema, item, allowed_types)
          end
        else
          FieldValidator.validate_value(field, column_schema, value, allowed_types)
        end
      end
    end
  end
end
