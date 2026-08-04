module ForestAdminDatasourceGraphqlHasura
  module Query
    # Converts a Forest Admin condition tree into a Hasura `_bool_exp` hash.
    class FilterConverter
      Nodes = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes
      Operators = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators

      def self.convert(condition_tree)
        new.convert(condition_tree)
      end

      def convert(condition_tree)
        return nil if condition_tree.nil?

        case condition_tree
        when Nodes::ConditionTreeBranch
          aggregator = condition_tree.aggregator == 'And' ? '_and' : '_or'
          { aggregator => condition_tree.conditions.map { |condition| convert(condition) } }
        when Nodes::ConditionTreeLeaf
          convert_leaf(condition_tree)
        else
          raise GraphqlError, "Unsupported condition tree node: #{condition_tree.class}"
        end
      end

      private

      # `_and`/`_or` only exist at bool_exp level, never inside a comparison
      # expression, so an operator needing two comparisons on the same field is
      # nested first and combined after.
      def convert_leaf(leaf)
        path = leaf.field.split(':')
        expression = operator_expression(leaf.operator, leaf.value)

        if expression.is_a?(Array)
          aggregator, comparisons = expression

          { aggregator => comparisons.map { |comparison| nest(path, comparison) } }
        else
          nest(path, expression)
        end
      end

      def nest(path, comparison)
        path.reverse.reduce(comparison) { |memo, part| { part => memo } }
      end

      def operator_expression(operator, value)
        case operator
        when Operators::EQUAL then value.nil? ? { '_is_null' => true } : { '_eq' => value }
        when Operators::NOT_EQUAL then value.nil? ? { '_is_null' => false } : { '_neq' => value }
        when Operators::GREATER_THAN, Operators::AFTER then { '_gt' => value }
        when Operators::LESS_THAN, Operators::BEFORE then { '_lt' => value }
        when Operators::GREATER_THAN_OR_EQUAL then { '_gte' => value }
        when Operators::LESS_THAN_OR_EQUAL then { '_lte' => value }
        when Operators::IN then in_expression(value)
        when Operators::NOT_IN then not_in_expression(value)
        when Operators::PRESENT then { '_is_null' => false }
        when Operators::MISSING, Operators::BLANK then { '_is_null' => true }
        when Operators::LIKE then { '_like' => value }
        when Operators::I_LIKE then { '_ilike' => value }
        # Case-insensitive like the ActiveRecord datasource, whose `matches`
        # compiles to ILIKE on Postgres.
        when Operators::CONTAINS, Operators::I_CONTAINS then { '_ilike' => "%#{escape_pattern(value)}%" }
        when Operators::NOT_CONTAINS, Operators::NOT_I_CONTAINS then { '_nilike' => "%#{escape_pattern(value)}%" }
        when Operators::STARTS_WITH, Operators::I_STARTS_WITH then { '_ilike' => "#{escape_pattern(value)}%" }
        when Operators::ENDS_WITH, Operators::I_ENDS_WITH then { '_ilike' => "%#{escape_pattern(value)}" }
        else
          raise GraphqlError, "Unsupported operator: #{operator}"
        end
      end

      # `IN (NULL, ...)` never matches NULL rows in Postgres. The toolkit relies
      # on this shape to emulate Blank/Present on text columns.
      def in_expression(value)
        values = Array(value)
        return { '_in' => values } unless values.include?(nil)

        others = values.compact
        return { '_is_null' => true } if others.empty?

        ['_or', [{ '_is_null' => true }, { '_in' => others }]]
      end

      def not_in_expression(value)
        values = Array(value)
        return { '_nin' => values } unless values.include?(nil)

        others = values.compact
        return { '_is_null' => false } if others.empty?

        ['_and', [{ '_is_null' => false }, { '_nin' => others }]]
      end

      # Someone searching "100%" means the literal string, not "contains 100".
      def escape_pattern(value)
        value.to_s.gsub(/[\\%_]/) { |match| "\\#{match}" }
      end
    end
  end
end
