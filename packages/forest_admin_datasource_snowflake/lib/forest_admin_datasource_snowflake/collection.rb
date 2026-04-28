require 'odbc'
require 'date'
require 'json'

module ForestAdminDatasourceSnowflake
  class Collection < ForestAdminDatasourceToolkit::Collection
    READ_ONLY_MESSAGE = 'forest_admin_datasource_snowflake is read-only.'.freeze
    ReadOnlyError = ForestAdminDatasourceToolkit::Exceptions::ForestException

    attr_reader :table_name

    def initialize(datasource, table_name)
      super
      @table_name = table_name
      @primary_keys = []
      @json_columns = []
      fetch_fields
      enable_count
    end

    def list(_caller, filter, projection)
      sql, binds = Utils::Query.new(self, projection: projection, filter: filter).to_sql
      execute_to_hashes(sql, binds, projection.to_a)
    end

    def aggregate(_caller, filter, aggregation, limit = nil)
      sql, binds, group_columns = Utils::Query.new(
        self,
        filter: filter,
        aggregation: aggregation,
        limit: limit
      ).to_aggregate_sql

      raw_rows = execute_raw(sql, binds)
      raw_rows.map do |row|
        value = coerce_value(row.first)
        group_hash = group_columns.each_with_index.to_h { |col, i| [col, coerce_for_column(col, row[i + 1])] }
        { 'value' => value, 'group' => group_hash }
      end
    end

    def create(_caller, _data) = raise(ReadOnlyError, READ_ONLY_MESSAGE)
    def update(_caller, _filter, _data) = raise(ReadOnlyError, READ_ONLY_MESSAGE)
    def delete(_caller, _filter) = raise(ReadOnlyError, READ_ONLY_MESSAGE)

    private

    def fetch_fields
      rows = @datasource.with_connection do |conn|
        stmt = conn.columns(@table_name)
        begin
          stmt.fetch_all || []
        ensure
          stmt.drop
        end
      end

      native_types = @datasource.fetch_snowflake_native_types(@table_name)
      pk_name = (rows.find { |r| r[3].to_s.casecmp('id').zero? } || rows.first)&.dig(3)

      rows.each do |row|
        column_name = row[3]
        odbc_type   = row[4]
        nullable    = row[10] != 0

        forest_type = Parser::Column.forest_type_for_snowflake_native(native_types[column_name]) ||
                      Parser::Column.forest_type_for(odbc_type)
        @json_columns << column_name if forest_type == 'Json'

        field = ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
          column_type: forest_type,
          filter_operators: Parser::Column.operators_for_column_type(forest_type),
          is_primary_key: column_name == pk_name,
          is_read_only: true,
          is_sortable: true,
          default_value: nil,
          enum_values: [],
          validation: nullable ? [] : [{ operator: 'Present' }]
        )
        @primary_keys << column_name if field.is_primary_key
        add_field(column_name, field)
      end
    end

    def execute_to_hashes(sql, binds, projected_columns)
      rows = execute_raw(sql, binds)
      rows.map { |row| projected_columns.each_with_index.to_h { |col, i| [col, coerce_for_column(col, row[i])] } }
    end

    def coerce_for_column(column_name, value)
      return parse_json_value(value) if @json_columns.include?(column_name)

      coerce_value(value)
    end

    def coerce_value(value)
      case value
      when ::ODBC::TimeStamp
        ::Time.utc(value.year, value.month, value.day, value.hour, value.minute, value.second)
      when ::ODBC::Date
        ::Date.new(value.year, value.month, value.day)
      when ::ODBC::Time
        format('%<h>02d:%<m>02d:%<s>02d', h: value.hour, m: value.minute, s: value.second)
      else
        value
      end
    end

    def parse_json_value(value)
      return value unless value.is_a?(String)

      JSON.parse(value)
    rescue JSON::ParserError
      value
    end

    def execute_raw(sql, binds)
      @datasource.with_connection do |conn|
        stmt = conn.prepare(sql)
        begin
          stmt.execute(*binds)
          stmt.fetch_all || []
        ensure
          stmt.drop
        end
      end
    end
  end
end
