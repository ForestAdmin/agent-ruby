require 'date'
require 'time'
require 'openssl'

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

        return PrimitiveTypes::BINARY if value.is_a?(buffer)

        return PrimitiveTypes::JSON if value.is_a?(Hash) && type_context.is_a?(Array) && type_context.first.is_a?(Hash)

        return PrimitiveTypes::JSON if value.is_a?(Hash) && type_context.is_a?(Hash)

        return PrimitiveTypes::JSON if value.is_a?(Array)

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

          return PrimitiveTypes::UUID if uuid?(value)

          return get_date_type(value) if valid_date?(value) && [PrimitiveTypes::DATE, PrimitiveTypes::DATE_ONLY,
                                                                PrimitiveTypes::TIME_ONLY].include?(type_context)

          return PrimitiveTypes::POINT if point?(value, type_context)

          PrimitiveTypes::STRING
        end

        def valid_date?(value)
          date?(value) || time?(value)
        end

        def date?(value)
          true if Date.parse(value)
        rescue ArgumentError
          false
        end

        def time?(value)
          true if Time.parse(value)
        rescue ArgumentError
          false
        end

        def number?(value)
          true if Float(value)
        rescue ArgumentError
          false
        end

        def point?(value, type_context)
          potential_point = value.split(',')

          potential_point.length == 2 && type_context == PrimitiveTypes::POINT && potential_point.all? do |point|
            number?(point) && get(point.to_i, PrimitiveTypes::NUMBER) == PrimitiveTypes::NUMBER
          end
        end

        def uuid?(uuid)
          format = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

          true if format.match?(uuid.to_s.downcase)
        end

        def buffer
          if defined?(IO::Buffer)
            IO::Buffer
          else
            OpenSSL::Buffering::Buffer
          end
        end
      end
    end
  end
end
