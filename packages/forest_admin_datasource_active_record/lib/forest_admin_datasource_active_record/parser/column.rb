module ForestAdminDatasourceActiveRecord
  module Parser
    module Column
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      TYPES = {
        boolean: 'Boolean',
        datetime: 'Date',
        timestamptz: 'Date',
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

        if TYPES.key?(column.type)
          type = TYPES[column.type]
        else
          type = TYPES[:string]
          ForestAdminAgent::Facades::Container.logger.log(
            'Info',
            "unknown type '#{column.type}' for field named '#{column.name}', '#{TYPES[:string]}' type use by default"
          )
        end

        is_array = column.respond_to?(:array) && column.array == true
        is_array ? [type] : type
      end

      def get_enum_values(model, column)
        return [] unless get_column_type(model, column) == 'Enum'

        if sti_column?(model, column)
          model.descendants.map(&:name)
        else
          model.defined_enums[column.name].keys
        end
      end

      def sti_column?(model, column)
        model.inheritance_column && column.name == model.inheritance_column
      end

      def normalize_default_value(column)
        case column.type
        when :boolean
          case column.default.to_s
          when '0', 'f', 'false'
            false
          when '1', 't', 'true'
            true
          else
            column.default
          end
        when :integer
          column.default.to_i
        when :float, :decimal
          column.default.to_f
        else
          column.default
        end
      end

      def operators_for_column_type(type)
        result = [Operators::PRESENT, Operators::BLANK, Operators::MISSING]
        equality = [Operators::EQUAL, Operators::NOT_EQUAL, Operators::IN, Operators::NOT_IN]

        if type.is_a? String
          orderables = [
            Operators::LESS_THAN,
            Operators::GREATER_THAN,
            Operators::LESS_THAN_OR_EQUAL,
            Operators::GREATER_THAN_OR_EQUAL
          ]
          strings = [
            Operators::CONTAINS,
            Operators::I_CONTAINS,
            Operators::NOT_CONTAINS,
            Operators::NOT_I_CONTAINS,
            Operators::STARTS_WITH,
            Operators::I_STARTS_WITH,
            Operators::ENDS_WITH,
            Operators::I_ENDS_WITH,
            Operators::LIKE,
            Operators::I_LIKE,
            Operators::MATCH,
            Operators::SHORTER_THAN,
            Operators::LONGER_THAN
          ]

          result += equality if %w[Boolean Binary Enum Uuid].include?(type)

          result = result + equality + orderables if %w[Date Dateonly Number].include?(type)

          result = result + equality + orderables + strings if %w[String].include?(type)
        end

        result += [Operators::EQUAL, Operators::NOT_EQUAL, Operators::INCLUDES_ALL] if type.is_a?(Array)

        result
      end
    end
  end
end
