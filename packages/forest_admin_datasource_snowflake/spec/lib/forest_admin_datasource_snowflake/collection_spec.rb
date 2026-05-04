require 'spec_helper'

RSpec.describe ForestAdminDatasourceSnowflake::Collection do
  let(:odbc_connection) { instance_double('ODBC::Connection') }
  let(:datasource) do
    ForestAdminDatasourceSnowflake::Datasource.new(
      conn_str: 'DRIVER={Snowflake};X=1',
      pool_size: 1,
      pool_timeout: 1
    )
  end
  let(:collection) { datasource.get_collection('BILLING_USAGE') }
  let(:driver_double)   { instance_double('ODBC::Driver') }
  let(:database_double) { instance_double('ODBC::Database') }

  let(:tables_stmt) { instance_double('ODBC::Statement', drop: nil) }
  let(:columns_stmt) { instance_double('ODBC::Statement', drop: nil) }
  let(:prepared_stmt) { instance_double('ODBC::Statement', drop: nil) }
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

    allow(tables_stmt).to receive(:fetch_all).and_return([
                                                           ['BILLING_POC', 'PUBLIC', 'BILLING_USAGE', 'TABLE', nil]
                                                         ])

    allow(odbc_connection).to receive_messages(tables: tables_stmt, columns: columns_stmt)
    allow(odbc_connection).to receive(:prepare).with(/ALTER SESSION/).and_return(session_stmt)
    allow(odbc_connection).to receive(:prepare).with(/INFORMATION_SCHEMA\.COLUMNS/).and_return(is_columns_stmt)
    allow(odbc_connection).to receive(:prepare).with('SHOW PRIMARY KEYS IN SCHEMA').and_return(pks_stmt)
    allow(odbc_connection).to receive(:prepare).with('SHOW IMPORTED KEYS IN SCHEMA').and_return(imported_keys_stmt)
    allow(columns_stmt).to receive(:fetch_all).and_return([
                                                            [nil, nil, 'BILLING_USAGE', 'ID',
                                                             ODBC::SQL_DECIMAL, nil, nil, nil, nil, nil, 0],
                                                            [nil, nil, 'BILLING_USAGE', 'CUSTOMER_ID',
                                                             ODBC::SQL_DECIMAL,  nil, nil, nil, nil, nil, 0],
                                                            [nil, nil, 'BILLING_USAGE', 'EVENT_TYPE',
                                                             ODBC::SQL_VARCHAR,  nil, nil, nil, nil, nil, 1]
                                                          ])
  end

  describe 'schema introspection' do
    it 'introspects all columns with Forest types and operators' do
      expect(collection.schema[:fields].keys).to contain_exactly('ID', 'CUSTOMER_ID', 'EVENT_TYPE')

      id_field = collection.schema[:fields]['ID']
      expect(id_field.column_type).to eq('Number')
      expect(id_field.is_primary_key).to be(true)
      expect(id_field.is_read_only).to be(true)
    end

    it 'overrides ODBC type with Snowflake native type for VARIANT/OBJECT/ARRAY (mapped to Json) and BINARY' do
      allow(is_columns_stmt).to receive(:fetch_all).and_return([
                                                                 ['META', 'VARIANT'],
                                                                 ['BLOB', 'BINARY']
                                                               ])
      allow(columns_stmt).to receive(:fetch_all).and_return([
                                                              [nil, nil, 'BILLING_USAGE', 'META',
                                                               ODBC::SQL_VARCHAR, nil, nil, nil, nil, nil, 1],
                                                              [nil, nil, 'BILLING_USAGE', 'BLOB',
                                                               ODBC::SQL_VARCHAR, nil, nil, nil, nil, nil, 1]
                                                            ])

      expect(collection.schema[:fields]['META'].column_type).to eq('Json')
      expect(collection.schema[:fields]['BLOB'].column_type).to eq('Binary')
    end

    it 'falls back to ODBC type when the column is not in the Snowflake-native override list' do
      allow(is_columns_stmt).to receive(:fetch_all).and_return([['ID', 'NUMBER']])

      expect(collection.schema[:fields]['ID'].column_type).to eq('Number')
    end

    it 'returns invalid JSON unchanged so a malformed row does not crash the list' do
      allow(is_columns_stmt).to receive(:fetch_all).and_return([['META', 'VARIANT']])
      allow(columns_stmt).to receive(:fetch_all).and_return([
                                                              [nil, nil, 'BILLING_USAGE', 'META',
                                                               ODBC::SQL_VARCHAR, nil, nil, nil, nil, nil, 1]
                                                            ])
      allow(odbc_connection).to receive(:prepare).with(/FROM "BILLING_USAGE"/).and_return(prepared_stmt)
      allow(prepared_stmt).to receive(:execute)
      allow(prepared_stmt).to receive(:fetch_all).and_return([['not-json']])

      result = collection.list(:caller, Filter.new, Projection.new(['META']))
      expect(result.first['META']).to eq('not-json')
    end

    it 'honors a Snowflake-declared primary key over the "id" / first-column fallback' do
      allow(pks_stmt).to receive(:fetch_all).and_return([
                                                          [Time.now, 'DB', 'PUBLIC', 'BILLING_USAGE', 'CUSTOMER_ID',
                                                           1, 'pk1', 'rely', '']
                                                        ])

      expect(collection.schema[:fields]['CUSTOMER_ID'].is_primary_key).to be(true)
      expect(collection.schema[:fields]['ID'].is_primary_key).to be(false)
    end

    it 'honors an operator-supplied primary_keys override above the Snowflake declaration' do
      allow(pks_stmt).to receive(:fetch_all).and_return([
                                                          [Time.now, 'DB', 'PUBLIC', 'BILLING_USAGE', 'CUSTOMER_ID',
                                                           1, 'pk1', 'rely', '']
                                                        ])

      ds = ForestAdminDatasourceSnowflake::Datasource.new(
        conn_str: 'DRIVER={X}',
        pool_size: 1,
        primary_keys: { 'BILLING_USAGE' => 'EVENT_TYPE' }
      )
      coll = ds.get_collection('BILLING_USAGE')

      expect(coll.schema[:fields]['EVENT_TYPE'].is_primary_key).to be(true)
      expect(coll.schema[:fields]['CUSTOMER_ID'].is_primary_key).to be(false)
      expect(coll.schema[:fields]['ID'].is_primary_key).to be(false)
    end

    it 'flags every column of a composite primary key declared in Snowflake' do
      allow(pks_stmt).to receive(:fetch_all).and_return([
                                                          [Time.now, 'DB', 'PUBLIC', 'BILLING_USAGE', 'ID',
                                                           1, 'pk1', 'rely', ''],
                                                          [Time.now, 'DB', 'PUBLIC', 'BILLING_USAGE', 'CUSTOMER_ID',
                                                           2, 'pk1', 'rely', '']
                                                        ])

      expect(collection.schema[:fields]['ID'].is_primary_key).to be(true)
      expect(collection.schema[:fields]['CUSTOMER_ID'].is_primary_key).to be(true)
      expect(collection.schema[:fields]['EVENT_TYPE'].is_primary_key).to be(false)
    end

    it 'flags every column of a composite primary_keys override' do
      ds = ForestAdminDatasourceSnowflake::Datasource.new(
        conn_str: 'DRIVER={X}',
        pool_size: 1,
        primary_keys: { 'BILLING_USAGE' => %w[ID CUSTOMER_ID] }
      )
      coll = ds.get_collection('BILLING_USAGE')

      expect(coll.schema[:fields]['ID'].is_primary_key).to be(true)
      expect(coll.schema[:fields]['CUSTOMER_ID'].is_primary_key).to be(true)
      expect(coll.schema[:fields]['EVENT_TYPE'].is_primary_key).to be(false)
    end

    it 'designates the first column as primary key when no "id" exists' do
      allow(columns_stmt).to receive(:fetch_all).and_return([
                                                              [nil, nil, 'T', 'PK', ODBC::SQL_VARCHAR, nil, nil, nil,
                                                               nil, nil, 0],
                                                              [nil, nil, 'T', 'X', ODBC::SQL_VARCHAR, nil, nil, nil,
                                                               nil, nil, 1]
                                                            ])
      allow(tables_stmt).to receive(:fetch_all).and_return([
                                                             ['BILLING_POC', 'PUBLIC', 'T', 'TABLE', nil]
                                                           ])

      ds = ForestAdminDatasourceSnowflake::Datasource.new(conn_str: 'DRIVER={X}', pool_size: 1)
      coll = ds.get_collection('T')
      expect(coll.schema[:fields]['PK'].is_primary_key).to be(true)
      expect(coll.schema[:fields]['X'].is_primary_key).to be(false)
    end
  end

  describe '#list' do
    it 'prepares the SQL, binds positionally, and projects rows into hashes' do
      expected_sql = 'SELECT "ID", "CUSTOMER_ID" FROM "BILLING_USAGE" WHERE "CUSTOMER_ID" = ?'
      expect(odbc_connection).to receive(:prepare).with(expected_sql).and_return(prepared_stmt)
      expect(prepared_stmt).to receive(:execute).with(42)
      expect(prepared_stmt).to receive(:fetch_all).and_return([[1, 42], [2, 42]])

      filter = Filter.new(condition_tree: ConditionTreeLeaf.new('CUSTOMER_ID', Operators::EQUAL, 42))
      result = collection.list(:caller, filter, Projection.new(%w[ID CUSTOMER_ID]))

      expect(result).to eq([
                             { 'ID' => 1, 'CUSTOMER_ID' => 42 },
                             { 'ID' => 2, 'CUSTOMER_ID' => 42 }
                           ])
    end

    it 'returns an empty array when the query yields no rows' do
      allow(odbc_connection).to receive(:prepare).and_return(prepared_stmt)
      allow(prepared_stmt).to receive(:execute)
      allow(prepared_stmt).to receive(:fetch_all).and_return(nil)

      result = collection.list(:caller, Filter.new, Projection.new(['ID']))
      expect(result).to eq([])
    end

    it 'coerces ODBC::Date / ODBC::TimeStamp values to Ruby Date / Time so JSON serializes correctly' do
      odbc_date = ODBC::Date.new(2026, 4, 28)
      odbc_ts   = ODBC::TimeStamp.new(2026, 4, 28, 10, 30, 15)

      allow(odbc_connection).to receive(:prepare).with(/FROM "BILLING_USAGE"/).and_return(prepared_stmt)
      allow(prepared_stmt).to receive(:execute)
      allow(prepared_stmt).to receive(:fetch_all).and_return([[1, odbc_date, odbc_ts]])

      result = collection.list(:caller, Filter.new, Projection.new(%w[ID AS_OF_DATE OCCURRED_AT]))

      expect(result.first['AS_OF_DATE']).to be_a(Date).and eq(Date.new(2026, 4, 28))
      expect(result.first['OCCURRED_AT']).to be_a(Time).and eq(Time.utc(2026, 4, 28, 10, 30, 15))
    end

    it 'parses JSON-typed columns into Ruby objects so the UI receives structured data' do
      allow(is_columns_stmt).to receive(:fetch_all).and_return([
                                                                 ['ID', 'NUMBER'],
                                                                 ['META', 'VARIANT']
                                                               ])
      allow(columns_stmt).to receive(:fetch_all).and_return([
                                                              [nil, nil, 'BILLING_USAGE', 'ID',
                                                               ODBC::SQL_DECIMAL, nil, nil, nil, nil, nil, 0],
                                                              [nil, nil, 'BILLING_USAGE', 'META',
                                                               ODBC::SQL_VARCHAR, nil, nil, nil, nil, nil, 1]
                                                            ])
      allow(odbc_connection).to receive(:prepare).with(/FROM "BILLING_USAGE"/).and_return(prepared_stmt)
      allow(prepared_stmt).to receive(:execute)
      allow(prepared_stmt).to receive(:fetch_all).and_return([[1, '{"foo":1,"bar":[true,null]}']])

      result = collection.list(:caller, Filter.new, Projection.new(%w[ID META]))

      expect(result.first['META']).to eq({ 'foo' => 1, 'bar' => [true, nil] })
      expect(collection.schema[:fields]['META'].column_type).to eq('Json')
    end
  end

  describe '#aggregate' do
    it 'returns Forest-shaped {value, group} rows from the result set' do
      expected_sql = 'SELECT COUNT(*), "EVENT_TYPE" FROM "BILLING_USAGE" GROUP BY "EVENT_TYPE"'
      allow(odbc_connection).to receive(:prepare).with(expected_sql).and_return(prepared_stmt)
      allow(prepared_stmt).to receive(:execute)
      allow(prepared_stmt).to receive(:fetch_all).and_return([[12, 'login'], [3, 'purchase']])

      result = collection.aggregate(
        :caller,
        Filter.new,
        Aggregation.new(operation: 'Count', groups: [{ field: 'EVENT_TYPE' }])
      )

      expect(result).to eq([
                             { 'value' => 12, 'group' => { 'EVENT_TYPE' => 'login' } },
                             { 'value' => 3, 'group' => { 'EVENT_TYPE' => 'purchase' } }
                           ])
    end
  end

  describe 'write methods' do
    let(:read_only_error) { ForestAdminDatasourceToolkit::Exceptions::ForestException }

    it '#create raises a ForestException with a read-only message' do
      expect { collection.create(:caller, {}) }.to raise_error(read_only_error, /read-only/)
    end

    it '#update raises a ForestException with a read-only message' do
      expect { collection.update(:caller, Filter.new, {}) }.to raise_error(read_only_error, /read-only/)
    end

    it '#delete raises a ForestException with a read-only message' do
      expect { collection.delete(:caller, Filter.new) }.to raise_error(read_only_error, /read-only/)
    end

    it 'declares every column as is_read_only so Forest emits collection-level isReadOnly: true' do
      column_fields = collection.schema[:fields].values.select { |f| f.type == 'Column' }
      expect(column_fields).not_to be_empty
      expect(column_fields).to all(have_attributes(is_read_only: true))
    end
  end
end
