module ForestAdminDatasourceSnowflake
  module Parser
    module Column
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      SNOWFLAKE_NATIVE_TYPE_TO_FOREST = {
        'NUMBER' => 'Number',
        'DECIMAL' => 'Number',
        'NUMERIC' => 'Number',
        'INT' => 'Number',
        'INTEGER' => 'Number',
        'BIGINT' => 'Number',
        'SMALLINT' => 'Number',
        'TINYINT' => 'Number',
        'BYTEINT' => 'Number',
        'FLOAT' => 'Number',
        'FLOAT4' => 'Number',
        'FLOAT8' => 'Number',
        'DOUBLE' => 'Number',
        'DOUBLE PRECISION' => 'Number',
        'REAL' => 'Number',
        'BOOLEAN' => 'Boolean',
        'TEXT' => 'String',
        'VARCHAR' => 'String',
        'CHAR' => 'String',
        'CHARACTER' => 'String',
        'STRING' => 'String',
        'DATE' => 'Dateonly',
        'TIME' => 'Time',
        'DATETIME' => 'Date',
        'TIMESTAMP' => 'Date',
        'TIMESTAMP_NTZ' => 'Date',
        'TIMESTAMP_LTZ' => 'Date',
        'TIMESTAMP_TZ' => 'Date',
        'VARIANT' => 'Json',
        'OBJECT' => 'Json',
        'ARRAY' => 'Json',
        'BINARY' => 'Binary',
        'VARBINARY' => 'Binary',
        'GEOGRAPHY' => 'String',
        'GEOMETRY' => 'String',
        'VECTOR' => 'String'
      }.freeze

      module_function

      def forest_type_for_snowflake_native(snowflake_type)
        SNOWFLAKE_NATIVE_TYPE_TO_FOREST[snowflake_type.to_s.upcase] || 'String'
      end

      def operators_for_column_type(type)
        result = [Operators::PRESENT, Operators::BLANK, Operators::MISSING]
        equality = [Operators::EQUAL, Operators::NOT_EQUAL, Operators::IN, Operators::NOT_IN]
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
          Operators::SHORTER_THAN,
          Operators::LONGER_THAN
        ]

        return result unless type.is_a?(String)

        result += equality if %w[Boolean Binary Enum Uuid Json].include?(type)
        result += equality + orderables if %w[Date Dateonly Time Number].include?(type)
        result += equality + orderables + strings if type == 'String'

        result
      end
    end
  end
end
