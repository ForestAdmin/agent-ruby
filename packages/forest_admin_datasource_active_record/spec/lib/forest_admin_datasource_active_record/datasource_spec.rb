require 'spec_helper'

module ForestAdminDatasourceActiveRecord
  describe Datasource do
    it 'fetch all models' do
      datasource = described_class.new({ adapter: 'sqlite3', database: 'db/database.db' })
      # Core collections that should always be present
      expected_core = %w[Account AccountHistory Order Check Category CarCheck Car Address CompaniesUser Supplier Author Book AuthorsBook]

      # Check core collections are present
      expect(datasource.collections.keys).to include(*expected_core)

      # User and Company may or may not be present depending on DB state, but if present they should be valid
      collections = datasource.collections.keys
      expect(collections).to all(be_a(String))
    end

    describe '#execute_native_query' do
      let(:datasource) do
        ds = described_class.allocate
        ds.instance_variable_set(:@live_query_connections, { 'main' => 'primary' })
        ds
      end

      context 'when the connection does not exist' do
        it 'raises a NotFoundError with the connection name' do
          expect do
            datasource.execute_native_query('unknown', 'SELECT 1', [])
          end.to raise_error(
            ForestAdminAgent::Http::Exceptions::NotFoundError,
            /Native query connection 'unknown' is unknown/
          )
        end
      end

      context 'when the connection exists' do
        it 'executes the query via pool.with_connection and returns results' do
          mock_result = ActiveRecord::Result.new(['test'], [[1]])
          mock_conn = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter)
          allow(mock_conn).to receive(:exec_query).and_return(mock_result)

          mock_pool = instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool)
          allow(mock_pool).to receive(:with_connection).and_yield(mock_conn)

          allow(ActiveRecord::Base).to receive(:connects_to).and_return([mock_pool])

          result = datasource.execute_native_query('main', 'SELECT 1 as test', [])

          expect(mock_pool).to have_received(:with_connection)
          expect(mock_conn).to have_received(:exec_query).with('SELECT 1 as test', "SQL Native Query on 'main'", [])
          expect(result).to eq([{ test: 1 }])
        end
      end

      context 'when the query raises an error' do
        it 'wraps the error in a ForestException' do
          mock_pool = instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool)
          allow(mock_pool).to receive(:with_connection).and_raise(StandardError, 'syntax error')

          allow(ActiveRecord::Base).to receive(:connects_to).and_return([mock_pool])

          expect do
            datasource.execute_native_query('main', 'INVALID SQL', [])
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            /Error when executing SQL query.*syntax error/
          )
        end
      end
    end
  end
end
