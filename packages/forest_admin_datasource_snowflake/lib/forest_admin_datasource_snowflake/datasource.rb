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
      /timeout expired/i
    ].freeze

    SYSTEM_SCHEMAS = %w[INFORMATION_SCHEMA].freeze

    attr_reader :pool

    def initialize(conn_str:, tables: nil, schema: nil,
                   pool_size: DEFAULT_POOL_SIZE, pool_timeout: DEFAULT_POOL_TIMEOUT,
                   statement_timeout: nil, introspect_relations: false)
      super()
      @conn_str             = conn_str
      @tables_filter        = tables&.map(&:to_s)&.map(&:upcase)
      @schema_override      = schema
      @statement_timeout    = statement_timeout
      @introspect_relations = introspect_relations
      @pool                 = ConnectionPool.new(size: pool_size, timeout: pool_timeout) do
        open_connection(conn_str)
      end

      generate_collections
      discover_relations if @introspect_relations
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

    def open_connection(conn_str)
      attrs  = conn_str.split(';').reject(&:empty?).to_h { |option| option.split('=', 2) }
      driver = ::ODBC::Driver.new
      driver.name  = 'odbc'
      driver.attrs = attrs
      conn = ::ODBC::Database.new.drvconnect(driver)
      apply_session_settings(conn)
      conn
    end

    def apply_session_settings(conn)
      run_session_statement(conn, "ALTER SESSION SET TIMEZONE = 'UTC'")
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
          .select { |t| @tables_filter.nil? || @tables_filter.include?(t[:name].to_s.upcase) }
          .map { |t| t[:name] }
      end
    end
  end
end
