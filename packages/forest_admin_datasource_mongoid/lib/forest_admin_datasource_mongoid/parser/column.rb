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
        # if model.respond_to?(:defined_enums) &&
        #    model.defined_enums.key?(column.name)
        #   return 'Enum'
        # end

        # is_array = column.respond_to?(:array) && column.array == true
        # is_array ? "[#{TYPES[column.type]}]" : TYPES[column.type]
        TYPES[column.type.to_s] || 'String'
      end

      def get_default_value(column)
        if column.options.key?(:default)
          default = column.options[:default]

          return default.respond_to?(:call) ? default.call : default
        end

        nil
      end

      def get_enum_values(_column)
        []
        # if get_column_type(model, column) == 'Enum'
        #   if sti_column?(model, column)
        #     model.descendants.each { |sti_model| enum_values << sti_model.name }
        #   else
        #     model.defined_enums[column.name].each_key { |name| enum_values << name }
        #   end
        # end
      end

      def operators_for_column_type(type)
        result = [Operators::PRESENT, Operators::MISSING]
        equality = [Operators::EQUAL, Operators::NOT_EQUAL, Operators::IN, Operators::NOT_IN]

        if type.is_a? String
          orderables = [Operators::LESS_THAN, Operators::GREATER_THAN]
          strings = [Operators::LIKE, Operators::I_LIKE, Operators::NOT_CONTAINS]

          result += equality if %w[Boolean Binary Enum Uuid].include?(type)

          result = result + equality + orderables if %w[Date Dateonly Number].include?(type)

          result = result + equality + orderables + strings if %w[String].include?(type)
        end

        result = result + equality + ['Includes_All'] if type.is_a? Array

        result
      end
    end
  end
end
