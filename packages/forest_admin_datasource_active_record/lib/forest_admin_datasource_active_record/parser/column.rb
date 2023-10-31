module ForestAdminDatasourceActiveRecord
  module Parser
    module Column
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      TYPES = {
        boolean: 'Boolean',
        datetime: 'Date',
        date: 'Dateonly',
        integer: 'Number',
        float: 'Number',
        decimal: 'Number',
        json: 'Json',
        jsonb: 'Json',
        hstore: 'Json',
        string: 'String',
        text: 'String',
        citext: 'String',
        time: 'Time',
        uuid: 'Uuid',
        binary: 'Binary'
      }.freeze

      def get_column_type(model, column)
        if model.respond_to?(:defined_enums) &&
           model.defined_enums.key?(column.name)
          return 'Enum'
        end

        is_array = (column.respond_to?(:array) && column.array == true)
        is_array ? "[#{TYPES[column.type]}]" : TYPES[column.type]
      end

      def get_enum_values(model, column)
        enum_values = []
        if get_column_type(model, column) == 'Enum'
          if sti_column?(model, column)
            model.descendants.each { |sti_model| enum_values << sti_model.name }
          else
            model.defined_enums[column.name].each { |name, _value| enum_values << name }
          end
        end
        enum_values
      end

      def sti_column?(model, column)
        model.inheritance_column && column.name == model.inheritance_column
      end

      def operators_for_column_type(type)
        result = [Operators::PRESENT, Operators::MISSING]
        equality = [Operators::EQUAL, Operators::NOT_EQUAL, Operators::IN, Operators::NOT_IN]

        if type.is_a? String
          orderables = [Operators::LESS_THAN, Operators::GREATER_THAN]
          strings = [Operators::LIKE, Operators::I_LIKE, Operators::NOT_CONTAINS]

          result + equality if %w[Boolean Binary Enum Uuid].include?(type)

          result + equality + orderables if %w[Date Dateonly Number].include?(type)

          result + equality + orderables + strings if %w[String].include?(type)
        end

        result + equality + ['Includes_All'] if type.is_a? Array

        result
      end
    end
  end
end
