module ForestAdminDatasourceToolkit
  module Components
    module Query
      module ConditionTree
        class Operators
          EQUAL = 'Equal'.freeze
          NOT_EQUAL = 'Not_Equal'.freeze
          LESS_THAN = 'Less_Than'.freeze
          GREATER_THAN = 'Greater_Than'.freeze
          MATCH = 'Match'.freeze
          LIKE = 'Like'.freeze
          I_LIKE = 'ILike'.freeze
          NOT_CONTAINS = 'Not_Contains'.freeze
          CONTAINS = 'Contains'.freeze
          I_CONTAINS = 'IContains'.freeze
          LONGER_THAN = 'Longer_Than'.freeze
          SHORTER_THAN = 'Shorter_Than'.freeze
          INCLUDES_ALL = 'Includes_All'.freeze
          PRESENT = 'Present'.freeze
          BLANK = 'Blank'.freeze
          IN = 'In'.freeze
          NOT_IN = 'Not_In'.freeze
          STARTS_WITH = 'Starts_With'.freeze
          I_STARTS_WITH = 'IStarts_With'.freeze
          ENDS_WITH = 'Ends_With'.freeze
          I_ENDS_WITH = 'IEnds_With'.freeze
          MISSING = 'Missing'.freeze
          BEFORE = 'Before'.freeze
          AFTER = 'After'.freeze
          AFTER_X_HOURS_AGO = 'After_X_Hours_Ago'.freeze
          BEFORE_X_HOURS_AGO = 'Before_X_Hours_Ago'.freeze
          FUTURE = 'Future'.freeze
          PAST = 'Past'.freeze
          TODAY = 'Today'.freeze
          YESTERDAY = 'Yesterday'.freeze
          PREVIOUS_WEEK = 'Previous_Week'.freeze
          PREVIOUS_MONTH = 'Previous_Month'.freeze
          PREVIOUS_QUARTER = 'Previous_Quarter'.freeze
          PREVIOUS_YEAR = 'Previous_Year'.freeze
          PREVIOUS_WEEK_TO_DATE = 'Previous_Week_To_Date'.freeze
          PREVIOUS_MONTH_TO_DATE = 'Previous_Month_To_Date'.freeze
          PREVIOUS_QUARTER_TO_DATE = 'Previous_Quarter_To_Date'.freeze
          PREVIOUS_YEAR_TO_DATE = 'Previous_Year_To_Date'.freeze
          PREVIOUS_X_DAYS = 'Previous_X_Days'.freeze
          PREVIOUS_X_DAYS_TO_DATE = 'Previous_X_Days_To_Date'.freeze

          def self.all
            constants
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
