module ForestAdminDatasourceToolkit
  module Validations
    class Rules
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      BASE_OPERATORS = [Operators::BLANK, Operators::EQUAL, Operators::MISSING, Operators::NOT_EQUAL,
                        Operators::PRESENT].freeze

      ARRAY_OPERATORS = [Operators::IN, Operators::NOT_IN, Operators::INCLUDES_ALL].freeze

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
        Operators::BEFORE,
        Operators::AFTER
      ].freeze

      def self.get_allowed_operators_for_column_type(primitive_type = nil)
        allowed_operators = {
          PrimitiveType::STRING => [
            *Rules::BASE_OPERATORS,
            *Rules::ARRAY_OPERATORS,
            Operators::CONTAINS,
            Operators::NOT_CONTAINS,
            Operators::ENDS_WITH,
            Operators::STARTS_WITH,
            Operators::LONGER_THAN,
            Operators::SHORTER_THAN,
            Operators::LIKE,
            Operators::I_LIKE,
            Operators::I_CONTAINS,
            Operators::I_ENDS_WITH,
            Operators::I_STARTS_WITH
          ],
          PrimitiveType::NUMBER => [
            *Rules::BASE_OPERATORS,
            *Rules::ARRAY_OPERATORS,
            Operators::GREATER_THAN,
            Operators::LESS_THAN
          ],
          PrimitiveType::DATE => [
            *Rules::BASE_OPERATORS,
            *Rules::BASE_DATEONLY_OPERATORS,
            Operators::BEFORE_X_HOURS_AGO,
            Operators::AFTER_X_HOURS_AGO
          ],
          PrimitiveType::TIMEONLY => [
            *Rules::BASE_OPERATORS,
            Operators::LESS_THAN,
            Operators::GREATER_THAN
          ],
          PrimitiveType::JSON => [
            Operators::BLANK,
            Operators::MISSING,
            Operators::PRESENT
          ],
          PrimitiveType::DATEONLY => [*Rules::BASE_OPERATORS, *Rules::BASE_DATEONLY_OPERATORS],
          PrimitiveType::ENUM => [*Rules::BASE_OPERATORS, *Rules::ARRAY_OPERATORS],
          PrimitiveType::UUID => [*Rules::BASE_OPERATORS, *Rules::ARRAY_OPERATORS],
          PrimitiveType::BOOLEAN => Rules::BASE_OPERATORS,
          PrimitiveType::POINT => Rules::BASE_OPERATORS
        }

        primitive_type ? allowed_operators[primitive_type] : allowed_operators
      end

      def self.get_allowed_types_for_column_type(primitive_type = nil)
        allowed_types = {
          PrimitiveType::STRING => [PrimitiveType::STRING, nil],
          PrimitiveType::NUMBER => [PrimitiveType::NUMBER, nil],
          PrimitiveType::DATEONLY => [PrimitiveType::DATEONLY, nil],
          PrimitiveType::DATE => [PrimitiveType::DATE, nil],
          PrimitiveType::TIMEONLY => [PrimitiveType::TIMEONLY, nil],
          PrimitiveType::ENUM => [PrimitiveType::ENUM, nil],
          PrimitiveType::UUID => [PrimitiveType::UUID, nil],
          PrimitiveType::JSON => [PrimitiveType::JSON, nil],
          PrimitiveType::BOOLEAN => [PrimitiveType::BOOLEAN, nil],
          PrimitiveType::POINT => [PrimitiveType::POINT, nil]
        }

        primitive_type ? allowed_types[primitive_type] : allowed_types
      end

      def self.compute_allowed_types_for_operators
        get_allowed_operators_for_column_type.keys.each_with_object({}) do |type, result|
          allowed_operators = get_allowed_operators_for_column_type(type)
          allowed_operators.each do |operator|
            if result[operator]
              result[operator] << type
            else
              result[operator] = [type]
            end
          end
        end
      end

      def self.get_allowed_types_for_operator(operator = nil)
        no_type_allowed = [nil]
        allowed_types = compute_allowed_types_for_operators
        merged = allowed_types.merge(
          Operators::IN => allowed_types[Operators::IN] + [nil],
          Operators::NOT_IN => allowed_types[Operators::NOT_IN] + [nil],
          Operators::INCLUDES_ALL => allowed_types[Operators::INCLUDES_ALL] + [nil],
          Operators::BLANK => no_type_allowed,
          Operators::MISSING => no_type_allowed,
          Operators::PRESENT => no_type_allowed,
          Operators::YESTERDAY => no_type_allowed,
          Operators::TODAY => no_type_allowed,
          Operators::PREVIOUS_QUARTER => no_type_allowed,
          Operators::PREVIOUS_YEAR => no_type_allowed,
          Operators::PREVIOUS_MONTH => no_type_allowed,
          Operators::PREVIOUS_WEEK => no_type_allowed,
          Operators::PAST => no_type_allowed,
          Operators::FUTURE => no_type_allowed,
          Operators::PREVIOUS_WEEK_TO_DATE => no_type_allowed,
          Operators::PREVIOUS_MONTH_TO_DATE => no_type_allowed,
          Operators::PREVIOUS_QUARTER_TO_DATE => no_type_allowed,
          Operators::PREVIOUS_YEAR_TO_DATE => no_type_allowed,
          Operators::PREVIOUS_X_DAYS_TO_DATE => ['Number'],
          Operators::PREVIOUS_X_DAYS => ['Number'],
          Operators::BEFORE_X_HOURS_AGO => ['Number'],
          Operators::AFTER_X_HOURS_AGO => ['Number']
        )

        operator ? merged[operator] : merged
      end
    end
  end
end
