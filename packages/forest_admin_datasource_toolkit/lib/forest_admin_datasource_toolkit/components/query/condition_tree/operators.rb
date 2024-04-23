module ForestAdminDatasourceToolkit
  module Components
    module Query
      module ConditionTree
        class Operators
          EQUAL = 'equal'.freeze
          NOT_EQUAL = 'not_equal'.freeze
          LESS_THAN = 'less_than'.freeze
          GREATER_THAN = 'greater_than'.freeze
          MATCH = 'match'.freeze
          LIKE = 'like'.freeze
          I_LIKE = 'i_like'.freeze
          NOT_CONTAINS = 'not_contains'.freeze
          CONTAINS = 'contains'.freeze
          I_CONTAINS = 'i_contains'.freeze
          LONGER_THAN = 'longer_than'.freeze
          SHORTER_THAN = 'shorter_than'.freeze
          INCLUDES_ALL = 'includes_all'.freeze
          PRESENT = 'present'.freeze
          BLANK = 'blank'.freeze
          IN = 'in'.freeze
          NOT_IN = 'not_in'.freeze
          STARTS_WITH = 'starts_with'.freeze
          I_STARTS_WITH = 'i_starts_with'.freeze
          ENDS_WITH = 'ends_with'.freeze
          I_ENDS_WITH = 'i_ends_with'.freeze
          MISSING = 'missing'.freeze
          BEFORE = 'before'.freeze
          AFTER = 'after'.freeze
          AFTER_X_HOURS_AGO = 'after_x_hours_ago'.freeze
          BEFORE_X_HOURS_AGO = 'before_x_hours_ago'.freeze
          FUTURE = 'future'.freeze
          PAST = 'past'.freeze
          TODAY = 'today'.freeze
          YESTERDAY = 'yesterday'.freeze
          PREVIOUS_WEEK = 'previous_week'.freeze
          PREVIOUS_MONTH = 'previous_month'.freeze
          PREVIOUS_QUARTER = 'previous_quarter'.freeze
          PREVIOUS_YEAR = 'previous_year'.freeze
          PREVIOUS_WEEK_TO_DATE = 'previous_week_to_date'.freeze
          PREVIOUS_MONTH_TO_DATE = 'previous_month_to_date'.freeze
          PREVIOUS_QUARTER_TO_DATE = 'previous_quarter_to_date'.freeze
          PREVIOUS_YEAR_TO_DATE = 'previous_year_to_date'.freeze
          PREVIOUS_X_DAYS = 'previous_x_days'.freeze
          PREVIOUS_X_DAYS_TO_DATE = 'previous_x_days_to_date'.freeze
          MATCH = 'match'.freeze

          def self.all
            constants.map { |constant| const_get(constant) }
          end

          def self.exist?(operator_value)
            all.include?(operator_value)
          end

          def self.interval_operators
            [
              self::TODAY,
              self::YESTERDAY,
              self::PREVIOUS_MONTH,
              self::PREVIOUS_QUARTER,
              self::PREVIOUS_WEEK,
              self::PREVIOUS_YEAR,
              self::PREVIOUS_MONTH_TO_DATE,
              self::PREVIOUS_QUARTER_TO_DATE,
              self::PREVIOUS_WEEK_TO_DATE,
              self::PREVIOUS_X_DAYS_TO_DATE,
              self::PREVIOUS_X_DAYS,
              self::PREVIOUS_YEAR_TO_DATE
            ]
          end

          def self.unique_operators
            [
              self::EQUAL,
              self::NOT_EQUAL,
              self::LESS_THAN,
              self::GREATER_THAN,
              self::MATCH,
              self::NOT_CONTAINS,
              self::LONGER_THAN,
              self::SHORTER_THAN,
              self::INCLUDES_ALL
            ]
          end
        end
      end
    end
  end
end
