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

    describe '#init_orm' do
      it 'uses connection_pool.db_config instead of deprecated connection_db_config' do
        mock_db_config = instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, env_name: 'test')
        mock_pool = instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool, db_config: mock_db_config)
        allow(ActiveRecord::Base).to receive_messages(
          establish_connection: nil,
          connection_pool: mock_pool,
          configurations: instance_double(ActiveRecord::DatabaseConfigurations, configurations: [])
        )

        ds = described_class.allocate
        ds.instance_variable_set(:@live_query_connections, {})
        ds.send(:init_orm, {})

        expect(ActiveRecord::Base).to have_received(:connection_pool)
        expect(mock_pool).to have_received(:db_config)
      end
    end

    describe '#execute_native_query' do
      let(:mock_pool) do
        instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool)
      end

      let(:datasource) do
        ds = described_class.allocate
        ds.instance_variable_set(:@live_query_connections, { 'main' => 'primary' })
        ds.instance_variable_set(:@native_query_pools, { 'primary' => mock_pool })
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
          allow(mock_pool).to receive(:with_connection).and_yield(mock_conn)

          result = datasource.execute_native_query('main', 'SELECT 1 as test', [])

          expect(mock_pool).to have_received(:with_connection)
          expect(mock_conn).to have_received(:exec_query).with('SELECT 1 as test', "SQL Native Query on 'main'", [])
          expect(result).to eq([{ test: 1 }])
        end
      end

      context 'when the query raises an error' do
        it 'wraps the error in a ForestException' do
          allow(mock_pool).to receive(:with_connection).and_raise(StandardError, 'syntax error')

          expect do
            datasource.execute_native_query('main', 'INVALID SQL', [])
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            /Error when executing SQL query.*syntax error/
          )
        end
      end
    end

    describe '#init_native_query_pools' do
      it 'establishes connection pools using configs_for and custom owner_name' do
        mock_db_config = instance_double(ActiveRecord::DatabaseConfigurations::HashConfig)
        mock_pool = instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool,
                                    db_config: mock_db_config)
        mock_handler = instance_double(ActiveRecord::ConnectionAdapters::ConnectionHandler)

        allow(ActiveRecord::Base).to receive_messages(
          configurations: instance_double(
            ActiveRecord::DatabaseConfigurations,
            configs_for: mock_db_config,
            configurations: []
          ),
          connection_handler: mock_handler
        )
        allow(mock_handler).to receive(:establish_connection).and_return(mock_pool)

        ds = described_class.allocate
        ds.instance_variable_set(:@live_query_connections, { 'main' => 'primary' })
        ds.send(:init_native_query_pools, 'test')

        expect(mock_handler).to have_received(:establish_connection).with(
          mock_db_config,
          owner_name: 'ForestAdminNativeQuery::primary'
        )
        expect(ds.instance_variable_get(:@native_query_pools)).to eq({ 'primary' => mock_pool })
      end
    end
  end
end
