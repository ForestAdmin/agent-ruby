require 'date'
require 'time'

module ForestAdminDatasourceToolkit
  module Validations
    class TypeGetter
      include ForestAdminDatasourceToolkit::Schema::Concerns
      def self.get(value, type_context)
        return PrimitiveTypes::JSON if type_context == PrimitiveTypes::JSON

        return get_type_from_string(value, type_context) if value.is_a?(String)

        return PrimitiveTypes::NUMBER if value.is_a?(Numeric)

        return PrimitiveTypes::DATE if value.is_a?(Date)

        return PrimitiveTypes::BOOLEAN if value.is_a?(TrueClass) || value.is_a?(FalseClass)

        return PrimitiveTypes::BINARY if value.is_a?(IO::Buffer)

        nil
      end

      class << self
        include ForestAdminDatasourceToolkit::Schema::Concerns
        def get_date_type(value)
          return PrimitiveTypes::DATE_ONLY if date?(value) && Date.parse(value).iso8601 == value

          if time?(value) && (Time.parse(value).strftime('%H:%M:%S.%L') == value ||
            Time.parse(value).strftime('%H:%M:%S') == value)
            return PrimitiveTypes::TIME_ONLY
          end

          PrimitiveTypes::DATE
        end

        def get_type_from_string(value, type_context)
          return type_context if [PrimitiveTypes::ENUM, PrimitiveTypes::STRING].include?(type_context)

          return PrimitiveTypes::UUID if uuid_validate(value)

          return get_date_type(value) if valid_date?(value) && [PrimitiveTypes::DATE, PrimitiveTypes::DATE_ONLY,
                                                                PrimitiveTypes::TIME_ONLY].include?(type_context)

          return PrimitiveTypes::POINT if point?(value, type_context)

          PrimitiveTypes::STRING
        end

        def valid_date?(value)
          date?(value) || time?(value)
        end

        def date?(value)
          Date.parse(value)
          true
        rescue ArgumentError
          false
        end

        def time?(value)
          Time.parse(value)
          true
        rescue ArgumentError
          false
        end

        def point?(value, type_context)
          potential_point = value.split(',')

          potential_point.length == 2 && type_context == PrimitiveTypes::POINT && potential_point.all? do |point|
            get(point, PrimitiveTypes::NUMBER) == PrimitiveTypes::NUMBER
          end
        end

        def uuid_validate(uuid)
          format = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

          true if format.match?(uuid.to_s.downcase)
        end
      end
    end
  end
end
