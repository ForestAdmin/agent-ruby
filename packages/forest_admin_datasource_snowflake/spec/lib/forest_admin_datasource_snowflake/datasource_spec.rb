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
  let(:pks_stmt) { instance_double('ODBC::Statement', drop: nil, execute: nil, fetch_all: []) }
  let(:imported_keys_stmt) { instance_double('ODBC::Statement', drop: nil, execute: nil, fetch_all: []) }

  before do
    allow(ODBC::Driver).to receive(:new).and_return(driver_double)
    allow(driver_double).to receive(:name=)
    allow(driver_double).to receive(:attrs=)
    allow(ODBC::Database).to receive(:new).and_return(database_double)
    allow(database_double).to receive(:drvconnect).and_return(odbc_connection)

    allow(odbc_connection).to receive(:prepare).with(/ALTER SESSION/).and_return(session_stmt)
    allow(odbc_connection).to receive(:prepare).with(/^USE SCHEMA/).and_return(session_stmt)
    allow(odbc_connection).to receive(:prepare).with(/INFORMATION_SCHEMA\.COLUMNS/).and_return(is_columns_stmt)
    allow(odbc_connection).to receive(:prepare).with('SHOW PRIMARY KEYS IN SCHEMA').and_return(pks_stmt)
    allow(odbc_connection).to receive(:prepare).with('SHOW IMPORTED KEYS IN SCHEMA').and_return(imported_keys_stmt)

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

    it 'honors the Schema= attribute from the connection string as a table-list filter' do
      allow(tables_stmt).to receive(:fetch_all).and_return([
                                                             ['BILLING_POC', 'PUBLIC', 'A', 'TABLE', nil],
                                                             ['BILLING_POC', 'PRIVATE', 'B', 'TABLE', nil]
                                                           ])
      ds = described_class.new(
        conn_str: 'DRIVER={Snowflake};Schema=PRIVATE',
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

    it 'aligns the session schema with the Schema= attribute (USE SCHEMA) so introspection targets the right schema' do
      expect(odbc_connection).to receive(:prepare).with('USE SCHEMA "ANALYTICS"').and_return(alter_stmt)

      described_class.new(conn_str: 'DRIVER={X};Schema=ANALYTICS', pool_size: 1)
    end

    it 'does not run USE SCHEMA when no Schema= attribute is present in the connection string' do
      expect(odbc_connection).not_to receive(:prepare).with(/^USE SCHEMA/)
      described_class.new(conn_str: 'DRIVER={X}', pool_size: 1)
    end

    it 'recognises the Schema= attribute case-insensitively in the connection string' do
      expect(odbc_connection).to receive(:prepare).with('USE SCHEMA "ANALYTICS"').and_return(alter_stmt)

      described_class.new(conn_str: 'DRIVER={X};SCHEMA=ANALYTICS', pool_size: 1)
    end
  end

  describe '#primary_keys_for' do
    it 'returns the operator-supplied override (case-insensitive table lookup) above all else' do
      ds = described_class.new(
        conn_str: 'DRIVER={X}',
        pool_size: 1,
        primary_keys: { 'billing_usage' => 'CUSTOMER_ID' }
      )

      expect(ds.primary_keys_for('BILLING_USAGE')).to eq(['CUSTOMER_ID'])
    end

    it 'accepts an array in the operator override for composite primary keys' do
      ds = described_class.new(
        conn_str: 'DRIVER={X}',
        pool_size: 1,
        primary_keys: { 'orders' => %w[ORDER_ID PRODUCT_ID] }
      )

      expect(ds.primary_keys_for('ORDERS')).to eq(%w[ORDER_ID PRODUCT_ID])
    end

    it 'falls back to Snowflake-defined primary key when no override is supplied' do
      allow(pks_stmt).to receive(:fetch_all).and_return([
                                                          [Time.now, 'DB', 'PUBLIC', 'BILLING_USAGE', 'CUSTOMER_ID',
                                                           1, 'pk1', 'rely', '']
                                                        ])

      ds = described_class.new(conn_str: 'DRIVER={X}', pool_size: 1)
      expect(ds.primary_keys_for('BILLING_USAGE')).to eq(['CUSTOMER_ID'])
    end

    it 'preserves every column of a Snowflake-declared composite primary key, ordered by key_sequence' do
      allow(pks_stmt).to receive(:fetch_all).and_return([
                                                          [Time.now, 'DB', 'PUBLIC', 'ORDERS', 'CUSTOMER_ID',
                                                           2, 'pk1', 'rely', ''],
                                                          [Time.now, 'DB', 'PUBLIC', 'ORDERS', 'ORDER_ID',
                                                           1, 'pk1', 'rely', '']
                                                        ])

      ds = described_class.new(conn_str: 'DRIVER={X}', pool_size: 1)
      expect(ds.primary_keys_for('ORDERS')).to eq(%w[ORDER_ID CUSTOMER_ID])
    end

    it 'returns an empty array when neither override nor Snowflake declaration is available' do
      ds = described_class.new(conn_str: 'DRIVER={X}', pool_size: 1)
      expect(ds.primary_keys_for('UNRELATED_TABLE')).to eq([])
    end

    it 'silently skips when SHOW PRIMARY KEYS errors (e.g. permissions)' do
      allow(pks_stmt).to receive(:execute).and_raise(ODBC::Error, 'permission denied')

      ds = described_class.new(conn_str: 'DRIVER={X}', pool_size: 1)
      expect(ds.primary_keys_for('BILLING_USAGE')).to eq([])
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

    it 'retries on Snowflake auth token expiry so a fresh connection re-authenticates' do
      datasource
      attempts = 0

      result = datasource.with_connection do |_conn|
        attempts += 1
        raise ODBC::Error, '08001 (390114) Authentication token has expired.' if attempts == 1

        :reauthed
      end

      expect(result).to eq(:reauthed)
      expect(attempts).to eq(2)
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

  describe 'foreign-key auto-discovery' do
    let(:imported_keys_row) do
      [Time.now, 'DB', 'PUBLIC', 'INTERNAL_LOG', 'ID',
       'DB', 'PUBLIC', 'BILLING_USAGE', 'CUSTOMER_ID',
       1, 'NO ACTION', 'NO ACTION', 'fk1', 'pk1', 'NOT_DEFERRABLE', 'false', '']
    end

    it 'runs unconditionally and adds a ManyToOne field on the source collection per discovered FK' do
      allow(imported_keys_stmt).to receive(:fetch_all).and_return([imported_keys_row])

      ds = described_class.new(conn_str: 'DRIVER={X}', pool_size: 1)

      source = ds.get_collection('BILLING_USAGE')
      relation = source.schema[:fields]['customer_id_internal_log']
      expect(relation).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
      expect(relation.foreign_collection).to eq('INTERNAL_LOG')
      expect(relation.foreign_key).to eq('CUSTOMER_ID')
      expect(relation.foreign_key_target).to eq('ID')
    end

    it 'silently skips when the FK introspection query errors (e.g. permissions)' do
      allow(imported_keys_stmt).to receive(:execute).and_raise(ODBC::Error, 'permission denied')

      expect do
        described_class.new(conn_str: 'DRIVER={X}', pool_size: 1)
      end.not_to raise_error
    end
  end
end
