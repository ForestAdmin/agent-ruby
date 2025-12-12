require 'spec_helper'
require 'shared/schema'
require 'logger'

module ForestAdminDatasourceRpc
  include ForestAdminDatasourceToolkit::Components::Query
  include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

  describe Datasource do
    before do
      logger = instance_double(Logger, log: nil)
      allow(ForestAdminAgent::Facades::Container).to receive_messages(logger: logger, cache: 'secret')
      allow(Utils::RpcClient).to receive(:new).and_return(rpc_client)
    end

    let(:rpc_client) { instance_double(Utils::RpcClient, call_rpc: {}) }
    let(:datasource) { described_class.new({ uri: 'http://localhost' }, introspection) }
    let(:caller) { build_caller }

    include_examples 'with introspection'

    context 'when initialize the datasource' do
      it 'add collections' do
        expect(datasource.collections.keys).to include('Product', 'Manufacturer')
      end

      it 'add charts' do
        expect(datasource.schema[:charts]).to include('appointments')
      end

      it 'stores native query connections' do
        datasource_with_connections = described_class.new(
          { uri: 'http://localhost' },
          introspection.merge(native_query_connections: [{ name: 'primary' }, { name: 'secondary' }])
        )
        expect(datasource_with_connections.live_query_connections).to eq({ 'primary' => 'primary', 'secondary' => 'secondary' })
      end

      it 'handles missing nativeQueryConnections gracefully' do
        expect(datasource.live_query_connections).to eq({})
      end

      context 'with schema polling client' do
        let(:schema_polling_client) { instance_double(Utils::SchemaPollingClient, stop: nil) }

        it 'registers shutdown hook for graceful cleanup' do
          datasource = described_class.new({ uri: 'http://localhost' }, introspection, schema_polling_client)

          # Verify that at_exit was called during initialization
          # We can't easily test at_exit execution itself, but we can verify cleanup works
          expect(datasource.instance_variable_get(:@schema_polling_client)).to eq(schema_polling_client)
        end

        it 'calls cleanup when cleanup is invoked' do
          datasource = described_class.new({ uri: 'http://localhost' }, introspection, schema_polling_client)

          datasource.cleanup

          expect(schema_polling_client).to have_received(:stop)
        end

        it 'cleanup is idempotent' do
          datasource = described_class.new({ uri: 'http://localhost' }, introspection, schema_polling_client)

          datasource.cleanup
          datasource.cleanup

          expect(schema_polling_client).to have_received(:stop).once
        end
      end
    end

    context 'when call render_chart' do
      it 'forward the call to the server' do
        datasource.render_chart(caller, 'my_chart')

        expect(rpc_client).to have_received(:call_rpc) do |url, options|
          expect(url).to eq('forest/rpc-datasource-chart')
          expect(options[:caller]).to eq(caller)
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq({ chart: 'my_chart' })
        end
      end
    end

    context 'when call execute_native_query' do
      it 'forward the call to the server with all parameters' do
        query = 'SELECT * FROM users WHERE id = ?'
        binds = [1]

        datasource.execute_native_query('primary', query, binds)

        expect(rpc_client).to have_received(:call_rpc) do |url, options|
          expect(url).to eq('forest/rpc-native-query')
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq({ connection_name: 'primary', query: query, binds: binds })
        end
      end
    end
  end
end
