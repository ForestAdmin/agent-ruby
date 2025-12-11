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

      context 'when server is not running but introspection is provided (resilient deployment)' do
        let(:rpc_client) { instance_double(Utils::RpcClient, fetch_schema: nil) }
        let(:schema_polling_client) { instance_double(Utils::SchemaPollingClient, start: nil, stop: nil) }

        before do
          allow(Utils::SchemaPollingClient).to receive(:new).and_return(schema_polling_client)
          allow(rpc_client).to receive(:fetch_schema).and_raise(Faraday::ConnectionFailed.new('connection refused'))
        end

        it 'builds datasource using provided introspection' do
          datasource = described_class.build({ uri: 'http://localhost', introspection: introspection })

          expect(datasource).to be_a(ForestAdminDatasourceRpc::Datasource)
        end

        it 'creates collections from provided introspection' do
          datasource = described_class.build({ uri: 'http://localhost', introspection: introspection })

          expect(datasource.collections.keys).to include('Product', 'Manufacturer')
        end

        it 'logs warning about using provided introspection' do
          described_class.build({ uri: 'http://localhost', introspection: introspection })

          expect(ForestAdminAgent::Facades::Container.logger).to have_received(:log).with(
            'Warn',
            'RPC agent at http://localhost is unreachable, using provided introspection for resilient deployment.'
          )
        end

        it 'still initializes schema polling for when slave becomes available' do
          described_class.build({ uri: 'http://localhost', introspection: introspection })

          expect(Utils::SchemaPollingClient).to have_received(:new)
          expect(schema_polling_client).to have_received(:start)
        end

        it 'handles timeout errors and uses provided introspection' do
          allow(rpc_client).to receive(:fetch_schema).and_raise(Faraday::TimeoutError.new('timeout'))

          datasource = described_class.build({ uri: 'http://localhost', introspection: introspection })

          expect(datasource).to be_a(ForestAdminDatasourceRpc::Datasource)
          expect(datasource.collections.keys).to include('Product', 'Manufacturer')
        end

        it 'handles authentication errors and uses provided introspection' do
          allow(rpc_client).to receive(:fetch_schema).and_raise(
            ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient.new('auth failed')
          )

          datasource = described_class.build({ uri: 'http://localhost', introspection: introspection })

          expect(datasource).to be_a(ForestAdminDatasourceRpc::Datasource)
        end
      end

      context 'when server is running and introspection is also provided' do
        let(:schema_polling_client) { instance_double(Utils::SchemaPollingClient, start: nil, stop: nil) }
        let(:response) { Utils::SchemaResponse.new(introspection, 'etag123') }
        let(:rpc_client) { instance_double(Utils::RpcClient, fetch_schema: response) }

        before do
          allow(Utils::SchemaPollingClient).to receive(:new).and_return(schema_polling_client)
        end

        it 'prefers fetched schema over provided introspection' do
          # Create a different introspection to prove the fetched one is used
          different_introspection = {
            collections: [{ name: 'DifferentCollection', fields: {}, actions: {}, segments: [], charts: [] }],
            charts: [],
            rpc_relations: {}
          }

          datasource = described_class.build({ uri: 'http://localhost', introspection: different_introspection })

          # Should use the fetched schema (Product, Manufacturer) not the provided one (DifferentCollection)
          expect(datasource.collections.keys).to include('Product', 'Manufacturer')
          expect(datasource.collections.keys).not_to include('DifferentCollection')
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

        it 'uses ENV["SCHEMA_POLLING_INTERVAL"] when set' do
          ENV['SCHEMA_POLLING_INTERVAL'] = '30'

          described_class.build({ uri: 'http://localhost' })

          expect(Utils::SchemaPollingClient).to have_received(:new).with(
            'http://localhost',
            'secret',
            { polling_interval: 30 },
            any_args
          )
        ensure
          ENV.delete('SCHEMA_POLLING_INTERVAL')
        end

        it 'prioritizes options[:schema_polling_interval] over ENV' do
          ENV['SCHEMA_POLLING_INTERVAL'] = '30'

          described_class.build({ uri: 'http://localhost', schema_polling_interval: 120 })

          expect(Utils::SchemaPollingClient).to have_received(:new).with(
            'http://localhost',
            'secret',
            { polling_interval: 120 },
            any_args
          )
        ensure
          ENV.delete('SCHEMA_POLLING_INTERVAL')
        end
      end
    end
  end
end
