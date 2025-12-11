require 'spec_helper'
require 'shared/schema'
require 'logger'

module ForestAdminDatasourceRpc
  describe ForestAdminDatasourceRpc do
    it 'has a version number' do
      expect(described_class::VERSION).not_to be_nil
    end

    describe 'build' do
      before do
        logger = instance_double(Logger, log: nil)
        allow(ForestAdminAgent::Facades::Container).to receive_messages(logger: logger, cache: 'secret')
        allow(Utils::RpcClient).to receive(:new).and_return(rpc_client)
      end

      include_examples 'with introspection'

      context 'when server is running' do
        let(:schema_polling_client) { instance_double(Utils::SchemaPollingClient, start: nil, stop: nil) }
        let(:response) { Utils::SchemaResponse.new(introspection, 'etag123') }
        let(:rpc_client) { instance_double(Utils::RpcClient, fetch_schema: response) }

        before do
          allow(Utils::SchemaPollingClient).to receive(:new).and_return(schema_polling_client)
        end

        it 'build datasource' do
          datasource = described_class.build({ uri: 'http://localhost' })

          expect(datasource).to be_a(ForestAdminDatasourceRpc::Datasource)
        end

        it 'calls RPC client to get schema from /forest/rpc-schema' do
          described_class.build({ uri: 'http://localhost' })

          expect(rpc_client).to have_received(:fetch_schema).with('/forest/rpc-schema')
        end

        it 'creates datasource with collections from introspection' do
          datasource = described_class.build({ uri: 'http://localhost' })

          expect(datasource.collections.keys).to include('Product', 'Manufacturer')
        end

        it 'creates datasource with charts from introspection' do
          datasource = described_class.build({ uri: 'http://localhost' })

          expect(datasource.schema[:charts]).to eq(['appointments'])
        end

        it 'handles introspection with native_query_connections' do
          introspection_with_connections = introspection.merge(
            native_query_connections: [{ name: 'primary' }, { name: 'secondary' }]
          )
          response_with_connections = Utils::SchemaResponse.new(introspection_with_connections, 'etag123')
          allow(rpc_client).to receive(:fetch_schema).and_return(response_with_connections)

          datasource = described_class.build({ uri: 'http://localhost' })

          expect(datasource.live_query_connections).to eq({ 'primary' => 'primary', 'secondary' => 'secondary' })
        end

        it 'initializes schema polling client for schema updates' do
          described_class.build({ uri: 'http://localhost' })

          expect(Utils::SchemaPollingClient).to have_received(:new)
          expect(schema_polling_client).to have_received(:start)
        end
      end

      context 'when server is not running' do
        let(:rpc_client) { instance_double(Utils::RpcClient, fetch_schema: nil) }

        it 'returns empty datasource and logs error' do
          allow(rpc_client).to receive(:fetch_schema).and_raise('server not running')

          datasource = described_class.build({ uri: 'http://localhost' })

          expect(datasource).to be_a(ForestAdminDatasourceToolkit::Datasource)
          expect(ForestAdminAgent::Facades::Container.logger).to have_received(:log).with(
            'Error',
            a_string_matching(%r{Failed to get schema from RPC agent at http://localhost.*server not running})
          )
        end
      end

      context 'with schema polling interval configuration' do
        let(:response) { Utils::SchemaResponse.new(introspection, 'etag123') }
        let(:rpc_client) { instance_double(Utils::RpcClient, fetch_schema: response) }
        let(:schema_polling_client) { instance_double(Utils::SchemaPollingClient, start: nil) }

        before do
          allow(Utils::RpcClient).to receive(:new).and_return(rpc_client)
          allow(Utils::SchemaPollingClient).to receive(:new).and_return(schema_polling_client)
        end

        it 'uses default interval (600s) when no config provided' do
          described_class.build({ uri: 'http://localhost' })

          expect(Utils::SchemaPollingClient).to have_received(:new).with(
            'http://localhost',
            'secret',
            { polling_interval: 600 },
            any_args
          )
        end

        it 'uses options[:schema_polling_interval] when provided' do
          described_class.build({ uri: 'http://localhost', schema_polling_interval: 120 })

          expect(Utils::SchemaPollingClient).to have_received(:new).with(
            'http://localhost',
            'secret',
            { polling_interval: 120 },
            any_args
          )
        end

        it 'uses ENV["SCHEMA_POLLING_INTERVAL_SEC"] when set' do
          ENV['SCHEMA_POLLING_INTERVAL_SEC'] = '30'

          described_class.build({ uri: 'http://localhost' })

          expect(Utils::SchemaPollingClient).to have_received(:new).with(
            'http://localhost',
            'secret',
            { polling_interval: 30 },
            any_args
          )
        ensure
          ENV.delete('SCHEMA_POLLING_INTERVAL_SEC')
        end

        it 'prioritizes options[:schema_polling_interval] over ENV' do
          ENV['SCHEMA_POLLING_INTERVAL_SEC'] = '30'

          described_class.build({ uri: 'http://localhost', schema_polling_interval: 120 })

          expect(Utils::SchemaPollingClient).to have_received(:new).with(
            'http://localhost',
            'secret',
            { polling_interval: 120 },
            any_args
          )
        ensure
          ENV.delete('SCHEMA_POLLING_INTERVAL_SEC')
        end
      end
    end
  end
end
