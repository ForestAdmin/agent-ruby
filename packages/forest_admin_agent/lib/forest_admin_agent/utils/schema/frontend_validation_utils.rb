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
          return [] if column.validation.empty?

          rules = column.validation.map { |rule| simplify_rule(column.column_type, rule) }
          remove_duplicates_in_place(rules)

          rules.filter { |rule| rule.is_a?(Hash) && rule.key?(:operator) }
               .map { |rule| SUPPORTED[rule[:operator]].call(rule) }
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

            conditions = if tree.is_a? Nodes::ConditionTreeLeaf
                           [tree]
                         else
                           tree.conditions
                         end

            return conditions.filter { |c| c.is_a?(Nodes::ConditionTreeLeaf) }
                             .filter { |c| c.operator != Operators::EQUAL && c.operator != Operators::NOT_EQUAL }
                             .map { |c| simplify_rule(column_type, operator: c.operator, value: c.value) }
                             .first
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

        def self.remove_duplicates_in_place(rules)
          used = {}

          i = 0
          while i < rules.length
            rule = rules[i]
            if rule.is_a?(Hash) && rule.key?(:operator)
              if used.key?(rule[:operator])
                existing_rule = rules[used[rule[:operator]]]
                new_rule = rules.delete_at(i)

                merge_into(existing_rule, new_rule)
                # Adjust the index to account for the removed element
                i -= 1
              else
                used[rule[:operator]] = i
              end
            end
            i += 1
          end
        end

        # rubocop:disable Style/EmptyElse
        def self.merge_into(rule, new_rule)
          case rule[:operator]
          when Operators::GREATER_THAN, Operators::AFTER, Operators::LONGER_THAN
            rule[:value] = [rule[:value], new_rule[:value]].max
          when Operators::LESS_THAN, Operators::BEFORE, Operators::SHORTER_THAN
            rule[:value] = [rule[:value], new_rule[:value]].min
          when Operators::MATCH
            regex = rule[:value].gsub(/\W/, '')
            new_regex = new_rule[:value].gsub(/\W/, '')
            rule[:value] = "/^(?=#{regex})(?=#{new_regex}).*$/i"
          else
            # Ignore the rules that we can't deduplicate (we could log a warning here).
          end
        end
        # rubocop:enable Style/EmptyElse
      end
    end
  end
end
