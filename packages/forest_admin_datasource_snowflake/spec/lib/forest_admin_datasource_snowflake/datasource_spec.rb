require 'spec_helper'

RSpec.describe ForestAdminDatasourceSnowflake::Datasource do
  subject(:datasource) do
    described_class.new(
      conn_str: 'DRIVER={Snowflake};Server=acc.snowflakecomputing.com;UID=u;PWD=p',
      pool_size: 1,
      pool_timeout: 1
    )
  end

  let(:odbc_connection) { instance_double('ODBC::Connection') }
  let(:driver_double)   { instance_double('ODBC::Driver') }
  let(:database_double) { instance_double('ODBC::Database') }

  let(:tables_stmt) { instance_double('ODBC::Statement', drop: nil) }
  let(:columns_stmt) { instance_double('ODBC::Statement', drop: nil) }
  let(:session_stmt) { instance_double('ODBC::Statement', drop: nil, execute: nil) }
  let(:is_columns_stmt) { instance_double('ODBC::Statement', drop: nil, execute: nil, fetch_all: []) }

  before do
    allow(ODBC::Driver).to receive(:new).and_return(driver_double)
    allow(driver_double).to receive(:name=)
    allow(driver_double).to receive(:attrs=)
    allow(ODBC::Database).to receive(:new).and_return(database_double)
    allow(database_double).to receive(:drvconnect).and_return(odbc_connection)

    allow(odbc_connection).to receive(:prepare).with(/ALTER SESSION/).and_return(session_stmt)
    allow(odbc_connection).to receive(:prepare).with(/INFORMATION_SCHEMA\.COLUMNS/).and_return(is_columns_stmt)

    allow(tables_stmt).to receive(:fetch_all).and_return([
                                                           ['BILLING_POC', 'PUBLIC', 'BILLING_USAGE',
                                                            'TABLE', nil],
                                                           ['BILLING_POC', 'PUBLIC',             'INTERNAL_LOG',
                                                            'TABLE', nil],
                                                           ['BILLING_POC', 'INFORMATION_SCHEMA', 'COLUMNS',
                                                            'VIEW',  nil],
                                                           ['BILLING_POC', 'PUBLIC',             'IGNORE_ME',
                                                            'SYSTEM TABLE', nil]
                                                         ])

    allow(odbc_connection).to receive_messages(tables: tables_stmt, columns: columns_stmt)
    allow(columns_stmt).to receive(:fetch_all).and_return([
                                                            [nil, nil, 'BILLING_USAGE', 'ID',
                                                             ODBC::SQL_DECIMAL, nil, nil, nil, nil, nil, 0],
                                                            [nil, nil, 'BILLING_USAGE', 'CUSTOMER_ID',
                                                             ODBC::SQL_DECIMAL,  nil, nil, nil, nil, nil, 0],
                                                            [nil, nil, 'BILLING_USAGE', 'EVENT_TYPE',
                                                             ODBC::SQL_VARCHAR,  nil, nil, nil, nil, nil, 1],
                                                            [nil, nil, 'BILLING_USAGE', 'OCCURRED_AT',
                                                             ODBC::SQL_TIMESTAMP, nil, nil, nil, nil, nil, 1]
                                                          ])
  end

  describe 'introspection' do
    it 'exposes only user-schema, non-system tables as Forest collections' do
      expect(datasource.collections.keys).to contain_exactly('BILLING_USAGE', 'INTERNAL_LOG')
    end

    it 'honors the optional :tables whitelist (case-insensitive)' do
      ds = described_class.new(
        conn_str: 'DRIVER={Snowflake};X=1',
        tables: ['billing_usage'],
        pool_size: 1
      )
      expect(ds.collections.keys).to eq(['BILLING_USAGE'])
    end

    it 'honors the optional :schema filter' do
      allow(tables_stmt).to receive(:fetch_all).and_return([
                                                             ['BILLING_POC', 'PUBLIC', 'A', 'TABLE', nil],
                                                             ['BILLING_POC', 'PRIVATE', 'B', 'TABLE', nil]
                                                           ])
      ds = described_class.new(
        conn_str: 'DRIVER={Snowflake};X=1',
        schema: 'PRIVATE',
        pool_size: 1
      )
      expect(ds.collections.keys).to eq(['B'])
    end
  end

  describe '#with_connection' do
    it 'yields a connection from the pool' do
      datasource.with_connection do |conn|
        expect(conn).to be(odbc_connection)
      end
    end
  end

  describe 'connection pool' do
    it 'wraps connections in a ConnectionPool with the configured size' do
      expect(datasource.pool).to be_a(ConnectionPool)
    end
  end

  describe 'session settings' do
    let(:alter_stmt) { instance_double('ODBC::Statement', drop: nil, execute: nil) }

    it 'always normalizes the session timezone to UTC so TIMESTAMP_LTZ/TZ serialize consistently' do
      expect(odbc_connection).to receive(:prepare)
        .with("ALTER SESSION SET TIMEZONE = 'UTC'").and_return(alter_stmt)

      described_class.new(conn_str: 'DRIVER={X}', pool_size: 1)
    end

    it 'runs ALTER SESSION SET STATEMENT_TIMEOUT_IN_SECONDS on each new connection when set' do
      expect(odbc_connection).to receive(:prepare)
        .with('ALTER SESSION SET STATEMENT_TIMEOUT_IN_SECONDS = 60').and_return(alter_stmt)

      described_class.new(
        conn_str: 'DRIVER={X}',
        pool_size: 1,
        statement_timeout: 60
      )
    end

    it 'does not run STATEMENT_TIMEOUT_IN_SECONDS when statement_timeout is nil' do
      expect(odbc_connection).not_to receive(:prepare).with(/STATEMENT_TIMEOUT/)
      described_class.new(conn_str: 'DRIVER={X}', pool_size: 1)
    end
  end

  describe '#fetch_snowflake_native_types' do
    it 'returns COLUMN_NAME => DATA_TYPE from INFORMATION_SCHEMA.COLUMNS' do
      stmt = instance_double('ODBC::Statement', drop: nil, execute: nil)
      allow(odbc_connection).to receive(:prepare).with(/INFORMATION_SCHEMA\.COLUMNS/).and_return(stmt)
      allow(stmt).to receive(:fetch_all).and_return([%w[META VARIANT], %w[BLOB BINARY]])

      expect(datasource.fetch_snowflake_native_types('billing_usage')).to eq(
        'META' => 'VARIANT',
        'BLOB' => 'BINARY'
      )
    end

    it 'returns an empty hash when the query errors (lacking permissions, etc.)' do
      stmt = instance_double('ODBC::Statement', drop: nil)
      allow(odbc_connection).to receive(:prepare).with(/INFORMATION_SCHEMA\.COLUMNS/).and_return(stmt)
      allow(stmt).to receive(:execute).and_raise(ODBC::Error, 'permission denied')

      expect(datasource.fetch_snowflake_native_types('billing_usage')).to eq({})
    end
  end

  describe 'connection retry on lost connections' do
    it 'retries the block exactly once after a connection-lost ODBC error' do
      attempts = 0
      datasource

      result = datasource.with_connection do |_conn|
        attempts += 1
        raise ODBC::Error, 'Communication link failure' if attempts == 1

        :recovered
      end

      expect(result).to eq(:recovered)
      expect(attempts).to eq(2)
    end

    it 'cycles the pool between attempts so stale connections get closed' do
      datasource
      expect(datasource.pool).to receive(:reload).and_call_original

      attempts = 0
      datasource.with_connection do |_conn|
        attempts += 1
        raise ODBC::Error, 'Connection is closed' if attempts == 1
      end
    end

    it 'does not retry on errors that are not connection-related' do
      datasource
      attempts = 0

      expect do
        datasource.with_connection do |_conn|
          attempts += 1
          raise ODBC::Error, 'Syntax error at end of input'
        end
      end.to raise_error(ODBC::Error, /Syntax error/)

      expect(attempts).to eq(1)
    end

    it 'gives up after one retry and re-raises' do
      datasource
      attempts = 0

      expect do
        datasource.with_connection do |_conn|
          attempts += 1
          raise ODBC::Error, 'Communication link failure'
        end
      end.to raise_error(ODBC::Error)

      expect(attempts).to eq(2)
    end
  end

  describe 'introspect_relations' do
    let(:relation_stmt) { instance_double('ODBC::Statement', drop: nil) }

    let(:imported_keys_row) do
      [Time.now, 'DB', 'PUBLIC', 'INTERNAL_LOG', 'ID',
       'DB', 'PUBLIC', 'BILLING_USAGE', 'CUSTOMER_ID',
       1, 'NO ACTION', 'NO ACTION', 'fk1', 'pk1', 'NOT_DEFERRABLE', 'false', '']
    end

    before do
      allow(odbc_connection).to receive(:prepare)
        .with('SHOW IMPORTED KEYS IN SCHEMA').and_return(relation_stmt)
      allow(relation_stmt).to receive(:execute)
      allow(relation_stmt).to receive(:fetch_all).and_return([imported_keys_row])
    end

    it 'adds a ManyToOne field on the source collection per discovered FK' do
      ds = described_class.new(
        conn_str: 'DRIVER={X}',
        pool_size: 1,
        introspect_relations: true
      )

      source = ds.get_collection('BILLING_USAGE')
      relation = source.schema[:fields]['customer_id_internal_log']
      expect(relation).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
      expect(relation.foreign_collection).to eq('INTERNAL_LOG')
      expect(relation.foreign_key).to eq('CUSTOMER_ID')
      expect(relation.foreign_key_target).to eq('ID')
    end

    it 'silently skips when the FK introspection query errors (e.g. permissions)' do
      allow(relation_stmt).to receive(:execute).and_raise(ODBC::Error, 'permission denied')

      expect do
        described_class.new(
          conn_str: 'DRIVER={X}',
          pool_size: 1,
          introspect_relations: true
        )
      end.not_to raise_error
    end

    it 'is off by default - no FK query runs unless introspect_relations: true' do
      expect(odbc_connection).not_to receive(:prepare).with('SHOW IMPORTED KEYS IN SCHEMA')
      described_class.new(conn_str: 'DRIVER={X}', pool_size: 1)
    end
  end
end
