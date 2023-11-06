require 'digest/sha1'
require 'json'

module ForestAdminAgent
  module Utils
    module Schema
      class FrontendFilterable
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

        BASE_OPERATORS = [
          Operators::EQUAL, Operators::NOT_EQUAL, Operators::PRESENT, Operators::BLANK
        ].freeze

        BASE_DATEONLY_OPERATORS = [
          Operators::TODAY,
          Operators::YESTERDAY,
          Operators::PREVIOUS_X_DAYS,
          Operators::PREVIOUS_WEEK,
          Operators::PREVIOUS_MONTH,
          Operators::PREVIOUS_QUARTER,
          Operators::PREVIOUS_YEAR,
          Operators::PREVIOUS_X_DAYS_TO_DATE,
          Operators::PREVIOUS_WEEK_TO_DATE,
          Operators::PREVIOUS_MONTH_TO_DATE,
          Operators::PREVIOUS_QUARTER_TO_DATE,
          Operators::PREVIOUS_YEAR_TO_DATE,
          Operators::PAST,
          Operators::FUTURE,
          Operators::BEFORE_X_HOURS_AGO,
          Operators::AFTER_X_HOURS_AGO,
          Operators::BEFORE,
          Operators::AFTER
        ].freeze

        DATE_OPERATORS = BASE_OPERATORS + BASE_DATEONLY_OPERATORS

        OPERATOR_BY_TYPE = {
          'Binary' => BASE_OPERATORS,
          'Boolean' => BASE_OPERATORS,
          'Date' => DATE_OPERATORS,
          'Dateonly' => DATE_OPERATORS,
          'Uuid' => BASE_OPERATORS,
          'Enum' => BASE_OPERATORS + [Operators::IN],
          'Number' => BASE_OPERATORS + [Operators::IN, Operators::GREATER_THAN, Operators::LESS_THAN],
          'Timeonly' => BASE_OPERATORS + [Operators::GREATER_THAN, Operators::LESS_THAN],
          'String' => BASE_OPERATORS +
                      [
                        Operators::IN,
                        Operators::STARTS_WITH,
                        Operators::ENDS_WITH,
                        Operators::CONTAINS,
                        Operators::NOT_CONTAINS
                      ],
          'Json' => []
        }.freeze

        def self.filterable?(type, supported_operators = [])
          needed_operators = get_required_operators(type)

          !needed_operators.empty? && needed_operators.all? { |operator| supported_operators.include?(operator) }
        end

        def self.get_required_operators(type)
          return OPERATOR_BY_TYPE[type] if type.is_a?(String) && OPERATOR_BY_TYPE.key?(type)

          return ['Includes_All'] if type.is_a? Array

          []
        end
      end
    end
  end
end
