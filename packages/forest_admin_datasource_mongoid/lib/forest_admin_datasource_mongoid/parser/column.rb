module ForestAdminDatasourceMongoid
  module Parser
    module Column
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      TYPES = {
        'Array' => 'Json',
        'BSON::Binary' => 'Binary',
        'BigDecimal' => 'Number',
        'Mongoid::Boolean' => 'Boolean',
        'Date' => 'Date',
        'DateTime' => 'Date',
        'Float' => 'Number',
        'Hash' => 'Json',
        'Integer' => 'Number',
        'Object' => 'Json',
        'BSON::ObjectId' => 'String',
        'Range' => 'Json',
        'Regexp' => 'String',
        'Set' => 'Json',
        'String' => 'String',
        'Mongoid::StringifiedSymbol' => 'String',
        'Symbol' => 'String',
        'Time' => 'Date',
        'ActiveSupport::TimeWithZone' => 'Date'
      }.freeze

      def get_column_type(column)
        return 'String' if column.foreign_key?

        TYPES[column.type.to_s] || 'String'
      end

      def get_default_value(column)
        if column.options.key?(:default)
          default = column.options[:default]

          return default.respond_to?(:call) ? default.call : default
        end

        nil
      end

      def operators_for_column_type(type)
        default_operators = [Operators::PRESENT, Operators::EQUAL, Operators::NOT_EQUAL]
        in_operators = [Operators::IN, Operators::NOT_IN]
        string_operators = [Operators::MATCH, Operators::NOT_CONTAINS, Operators::NOT_I_CONTAINS]
        comparison_operators = [Operators::GREATER_THAN, Operators::LESS_THAN]
        result = []

        if type.is_a? String
          case type
          when 'Boolean', 'Binary', 'Json'
            result = default_operators
          when 'Date', 'Dateonly', 'Number'
            result = default_operators + in_operators + comparison_operators
          when 'Enum'
            result = default_operators + in_operators
          when 'String'
            result = default_operators + in_operators + string_operators
          end
        end

        result = default_operators if type.is_a? Array

        result
      end
    end
  end
end
