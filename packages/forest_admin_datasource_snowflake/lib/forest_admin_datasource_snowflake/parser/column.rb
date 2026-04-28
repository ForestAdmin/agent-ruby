require 'odbc'

module ForestAdminDatasourceSnowflake
  module Parser
    module Column
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      ODBC_TYPE_TO_FOREST = {
        ODBC::SQL_BIT => 'Boolean',
        ODBC::SQL_TINYINT => 'Number',
        ODBC::SQL_SMALLINT => 'Number',
        ODBC::SQL_INTEGER => 'Number',
        ODBC::SQL_BIGINT => 'Number',
        ODBC::SQL_NUMERIC => 'Number',
        ODBC::SQL_DECIMAL => 'Number',
        ODBC::SQL_DOUBLE => 'Number',
        ODBC::SQL_REAL => 'Number',
        ODBC::SQL_FLOAT => 'Number',
        ODBC::SQL_DATE => 'Dateonly',
        ODBC::SQL_TYPE_DATE => 'Dateonly',
        ODBC::SQL_TIME => 'Time',
        ODBC::SQL_TYPE_TIME => 'Time',
        ODBC::SQL_TIMESTAMP => 'Date',
        ODBC::SQL_TYPE_TIMESTAMP => 'Date',
        ODBC::SQL_CHAR => 'String',
        ODBC::SQL_VARCHAR => 'String',
        ODBC::SQL_LONGVARCHAR => 'String',
        ODBC::SQL_WCHAR => 'String',
        ODBC::SQL_WVARCHAR => 'String',
        ODBC::SQL_WLONGVARCHAR => 'String',
        ODBC::SQL_BINARY => 'Binary',
        ODBC::SQL_VARBINARY => 'Binary',
        ODBC::SQL_LONGVARBINARY => 'Binary',
        ODBC::SQL_GUID => 'Uuid'
      }.freeze

      SNOWFLAKE_VARIANT_TYPE = 2004
      ODBC_TYPE_TO_FOREST_WITH_SNOWFLAKE = ODBC_TYPE_TO_FOREST.merge(SNOWFLAKE_VARIANT_TYPE => 'Json').freeze

      SNOWFLAKE_NATIVE_TYPE_TO_FOREST = {
        'VARIANT' => 'Json',
        'OBJECT' => 'Json',
        'ARRAY' => 'Json',
        'BINARY' => 'Binary',
        'VARBINARY' => 'Binary'
      }.freeze

      module_function

      def forest_type_for(odbc_type)
        ODBC_TYPE_TO_FOREST_WITH_SNOWFLAKE[odbc_type] || 'String'
      end

      def forest_type_for_snowflake_native(snowflake_type)
        SNOWFLAKE_NATIVE_TYPE_TO_FOREST[snowflake_type.to_s.upcase]
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
