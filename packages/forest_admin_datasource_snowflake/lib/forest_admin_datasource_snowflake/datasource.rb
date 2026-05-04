require 'odbc'
require 'connection_pool'

module ForestAdminDatasourceSnowflake
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    DEFAULT_POOL_SIZE    = 5
    DEFAULT_POOL_TIMEOUT = 5

    CONNECTION_LOST_PATTERNS = [
      /Communication link failure/i,
      /Connection.*lost/i,
      /Connection is closed/i,
      /Session.*expired/i,
      /Session.*timed out/i,
      /Broken pipe/i,
      /Not connected/i,
      /timeout expired/i,
      /Authentication token has expired/i,
      /token.*expired/i
    ].freeze

    SYSTEM_SCHEMAS = %w[INFORMATION_SCHEMA].freeze

    attr_reader :pool

    def initialize(conn_str:,
                   pool_size: DEFAULT_POOL_SIZE, pool_timeout: DEFAULT_POOL_TIMEOUT,
                   statement_timeout: nil, primary_keys: nil)
      super()
      @schema_override        = extract_schema_from_conn_str(conn_str)
      @statement_timeout      = statement_timeout
      @primary_keys_override  = (primary_keys || {}).transform_keys { |k| k.to_s.upcase }
      @pool                   = ConnectionPool.new(size: pool_size, timeout: pool_timeout) do
        open_connection(conn_str)
      end

      generate_collections
      discover_relations
    end

    def with_connection(&block)
      retried = false
      begin
        @pool.with(&block)
      rescue ::ODBC::Error => e
        if !retried && connection_lost?(e)
          retried = true
          reset_pool!
          retry
        end
        raise
      end
    end

    def shutdown!
      @pool.shutdown { |conn| safe_disconnect(conn) }
    end

    def primary_key_for(table_name)
      upper = table_name.to_s.upcase
      return @primary_keys_override[upper] if @primary_keys_override.key?(upper)

      snowflake_primary_keys[upper]
    end

    def fetch_snowflake_native_types(table_name)
      with_connection do |conn|
        stmt = conn.prepare(
          'SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS ' \
          'WHERE TABLE_NAME = ? AND TABLE_SCHEMA = CURRENT_SCHEMA()'
        )
        begin
          stmt.execute(table_name.to_s.upcase)
          rows = stmt.fetch_all || []
          rows.to_h { |r| [r[0], r[1]] }
        ensure
          stmt.drop
        end
      end
    rescue ::ODBC::Error
      {}
    end

    private

    def snowflake_primary_keys
      @snowflake_primary_keys ||= fetch_snowflake_primary_keys
    end

    def fetch_snowflake_primary_keys
      with_connection do |conn|
        stmt = conn.prepare('SHOW PRIMARY KEYS IN SCHEMA')
        rows = begin
          stmt.execute
          stmt.fetch_all || []
        ensure
          stmt.drop
        end

        rows.group_by { |r| r[3].to_s.upcase }
            .transform_values { |table_rows| table_rows.min_by { |r| r[5].to_i }[4].to_s }
      end
    rescue ::ODBC::Error
      {}
    end

    def open_connection(conn_str)
      driver = ::ODBC::Driver.new
      driver.name  = 'odbc'
      driver.attrs = parse_conn_str(conn_str)
      conn = ::ODBC::Database.new.drvconnect(driver)
      apply_session_settings(conn)
      conn
    end

    def parse_conn_str(conn_str)
      conn_str.split(';').reject(&:empty?).to_h { |option| option.split('=', 2) }
    end

    def extract_schema_from_conn_str(conn_str)
      attrs = parse_conn_str(conn_str)
      pair  = attrs.find { |k, _| k.to_s.casecmp('schema').zero? }
      value = pair && pair[1]
      value if value && !value.empty?
    end

    def apply_session_settings(conn)
      run_session_statement(conn, "ALTER SESSION SET TIMEZONE = 'UTC'")
      run_session_statement(conn, "USE SCHEMA #{Utils::Identifier.quote(@schema_override)}") if @schema_override

      return unless @statement_timeout

      seconds = Integer(@statement_timeout)
      run_session_statement(conn, "ALTER SESSION SET STATEMENT_TIMEOUT_IN_SECONDS = #{seconds}")
    end

    def run_session_statement(conn, sql)
      stmt = conn.prepare(sql)
      begin
        stmt.execute
      ensure
        stmt.drop
      end
    end

    def connection_lost?(error)
      message = error.message.to_s
      CONNECTION_LOST_PATTERNS.any? { |pattern| pattern.match?(message) }
    end

    def reset_pool!
      @pool.reload { |conn| safe_disconnect(conn) }
    end

    def safe_disconnect(connection)
      connection.disconnect if connection.respond_to?(:disconnect)
    rescue StandardError
      nil
    end

    def generate_collections
      visible_tables.each do |table_name|
        add_collection(Collection.new(self, table_name))
      end
    end

    def discover_relations
      Parser::Relation.discover(self).each do |fk|
        source = collections[fk[:source_table]]
        next if source.nil? || collections[fk[:target_table]].nil?

        relation = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema.new(
          foreign_collection: fk[:target_table],
          foreign_key: fk[:source_column],
          foreign_key_target: fk[:target_column]
        )
        relation_name = "#{fk[:source_column]}_#{fk[:target_table]}".downcase
        source.add_field(relation_name, relation)
      end
    rescue ::ODBC::Error => e
      warn "[forest_admin_datasource_snowflake] FK introspection skipped: #{e.message}"
    end

    def visible_tables
      with_connection do |conn|
        stmt = conn.tables
        rows = begin
          stmt.fetch_all || []
        ensure
          stmt.drop
        end

        rows
          .map { |row| { catalog: row[0], schema: row[1], name: row[2], type: row[3] } }
          .reject { |t| SYSTEM_SCHEMAS.include?(t[:schema].to_s.upcase) }
          .reject { |t| t[:type].to_s.upcase == 'SYSTEM TABLE' }
          .select { |t| @schema_override.nil? || t[:schema].to_s.casecmp(@schema_override).zero? }
          .map { |t| t[:name] }
      end
    end
  end
end
