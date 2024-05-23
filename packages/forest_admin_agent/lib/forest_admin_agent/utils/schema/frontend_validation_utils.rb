module ForestAdminAgent
  module Utils
    module Schema
      class FrontendValidationUtils
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

        # Those operators depend on the current time so they won't work.
        # The reason is that we need now() to be evaluated at query time, not at schema generation time.
        EXCLUDED = [Operators::FUTURE, Operators::PAST, Operators::TODAY, Operators::YESTERDAY,
                    Operators::PREVIOUS_MONTH, Operators::PREVIOUS_QUARTER, Operators::PREVIOUS_WEEK,
                    Operators::PREVIOUS_X_DAYS, Operators::PREVIOUS_YEAR, Operators::AFTER_X_HOURS_AGO,
                    Operators::BEFORE_X_HOURS_AGO, Operators::PREVIOUS_X_DAYS_TO_DATE,
                    Operators::PREVIOUS_MONTH_TO_DATE, Operators::PREVIOUS_QUARTER_TO_DATE,
                    Operators::PREVIOUS_WEEK_TO_DATE, Operators::PREVIOUS_YEAR_TO_DATE].freeze

        SUPPORTED = {
          Operators::PRESENT => proc { { type: 'is present', message: 'Field is required' } },
          Operators::AFTER => proc do |rule|
            { type: 'is after', value: rule[:value], message: "Value must be after #{rule[:value]}" }
          end,
          Operators::BEFORE => proc do |rule|
            { type: 'is before', value: rule[:value], message: "Value must be before #{rule[:value]}" }
          end,
          Operators::CONTAINS => proc do |rule|
            { type: 'is contains', value: rule[:value], message: "Value must contain #{rule[:value]}" }
          end,
          Operators::GREATER_THAN => proc do |rule|
            { type: 'is greater than', value: rule[:value], message: "Value must be greater than #{rule[:value]}" }
          end,
          Operators::LESS_THAN => proc do |rule|
            { type: 'is less than', value: rule[:value], message: "Value must be lower than #{rule[:value]}" }
          end,
          Operators::LONGER_THAN => proc do |rule|
            { type: 'is longer than', value: rule[:value],
              message: "Value must be longer than #{rule[:value]} characters" }
          end,
          Operators::SHORTER_THAN => proc do |rule|
            {
              type: 'is shorter than',
              value: rule[:value],
              message: "Value must be shorter than #{rule[:value]} characters"
            }
          end,
          Operators::MATCH => proc do |rule|
            {
              type: 'is like', # `is like` actually expects a regular expression, not a 'like pattern'
              value: rule[:value].to_s,
              message: "Value must match #{rule[:value]}"
            }
          end
        }.freeze

        def self.convert_validation_list(column)
          return [] if column.validations.empty?

          rules = column.validations.dup.map { |rule| simplify_rule(column.column_type, rule) }
          remove_duplicates_in_place(rules).map { |rule| SUPPORTED[rule[:operator]].call(rule) }
        end

        def self.simplify_rule(column_type, rule)
          return [] if EXCLUDED.include?(rule[:operator])

          return rule if SUPPORTED.key?(rule[:operator])

          begin
            # Add the 'Equal|NotEqual' operators to unlock the `In|NotIn -> Match` replacement rules.
            # This is a bit hacky, but it allows to reuse the existing logic.
            operators = SUPPORTED.keys
            operators << Operators::EQUAL
            operators << Operators::NOT_EQUAL

            # Rewrite the rule to use only operators that the frontend supports.
            leaf = Nodes::ConditionTreeLeaf.new('field', rule[:operator], rule[:value])
            timezone = 'Europe/Paris' # we're sending the schema => use random tz
            tree = ConditionTreeEquivalent.get_equivalent_tree(leaf, operators, column_type, timezone)

            if tree.is_a? Nodes::ConditionTreeLeaf
              [tree]
            else
              tree.conditions
            end
          rescue StandardError
            # Just ignore errors, they mean that the operator is not supported by the frontend
            # and that we don't have an automatic conversion for it.
            #
            # In that case we fallback to just validating the data entry in the agent (which is better
            # than nothing but will not be as user friendly as the frontend validation).
          end

          # Drop the rule if we don't know how to convert it (we could log a warning here).
          []
        end

        # The frontend crashes when it receives multiple rules of the same type.
        # This method merges the rules which can be merged and drops the others.
        def self.remove_duplicates_in_place(rules)
          used = {}
          rules.each_with_index do |rule, key|
            if used.key?(rule[:operator])
              rule = rules[rule[:operator]]
              new_rule = rule
              rules.delete(key)
              rules[used[rule[:operator]]] = merge_into(rule, new_rule)
            else
              used[rule[:operator]] = key
            end
          end

          rules
        end

        def merge_into(rule, new_rule)
          if [Operators::GREATER_THAN, Operators::AFTER, Operators::LONGER_THAN].include? rule[:operator]
            rule[:value] = [rule[:value], new_rule[:value]].max
          elsif [Operators::LESS_THAN, Operators::BEFORE, Operators::SHORTER_THAN].include? rule[:operator]
            rule[:value] = [rule[:value], new_rule[:value]].min
          elsif rule[:operator] == Operators::MATCH
            # TODO
          end
          # else Ignore the rules that we can't deduplicate (we could log a warning here).

          rule
        end
      end
    end
  end
end
