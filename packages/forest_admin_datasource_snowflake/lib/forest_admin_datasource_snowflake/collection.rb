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
      rows = @datasource.snowflake_columns_for(@table_name)
      pk_names = resolve_primary_keys(rows)

      rows.each do |row|
        column_name    = row[1]
        snowflake_type = row[2]
        nullable       = row[3].to_s.casecmp('YES').zero?

        forest_type = Parser::Column.forest_type_for_snowflake_native(snowflake_type)
        @json_columns << column_name if forest_type == 'Json'

        field = ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
          column_type: forest_type,
          filter_operators: Parser::Column.operators_for_column_type(forest_type),
          is_primary_key: pk_names.include?(column_name),
          is_read_only: true,
          is_sortable: true,
          default_value: nil,
          enum_values: [],
          validation: nullable ? [] : [{ operator: 'Present' }]
        )
        add_field(column_name, field)
      end
    end

    def resolve_primary_keys(rows)
      column_names = rows.map { |r| r[1] }
      override = @datasource.primary_keys_override_for(@table_name)
      return resolve_override_primary_keys(override, column_names) if override

      declared_pks = @datasource.primary_keys_for(@table_name)
      matches = declared_pks.filter_map do |pk|
        column_names.find { |name| name.to_s.casecmp(pk.to_s).zero? }
      end
      return matches if matches.any?

      fallback = (rows.find { |r| r[1].to_s.casecmp('id').zero? } || rows.first)&.dig(1)
      fallback ? [fallback] : []
    end

    def resolve_override_primary_keys(override, column_names)
      override.map do |declared_pk|
        column_names.find { |name| name.to_s.casecmp(declared_pk.to_s).zero? } ||
          raise(ForestAdminDatasourceSnowflake::Error,
                "primary_keys override '#{declared_pk}' does not match any column on table " \
                "'#{@table_name}' (available: #{column_names.join(", ")})")
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
