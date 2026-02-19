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
      end

      include_examples 'with introspection'

      context 'with unknown options' do
        let(:schema_polling_client) { instance_double(Utils::SchemaPollingClient, start?: true, stop: nil, current_schema: introspection) }
        let(:logger) { ForestAdminAgent::Facades::Container.logger }

        before do
          allow(Utils::SchemaPollingClient).to receive(:new).and_return(schema_polling_client)
        end

        it 'logs a warning when unknown keys are passed' do
          described_class.build({ uri: 'http://localhost', url: 'http://localhost', foo: 'bar' })

          expect(logger).to have_received(:log).with(
            'Warn',
            a_string_matching(/Unknown option.*\burl\b.*\bfoo\b/)
          )
        end

        it 'logs a warning when a key does not exist in known options' do
          described_class.build({ uri: 'http://localhost', url: 'http://localhost' })

          expect(logger).to have_received(:log).with(
            'Warn',
            a_string_matching(/Unknown option.*url.*Known options are/)
          )
        end

        it 'does not log a warning when only known keys are passed' do
          described_class.build({ uri: 'http://localhost', auth_secret: 'secret', schema_polling_interval_sec: 60 })

          expect(logger).not_to have_received(:log).with('Warn', anything)
        end
      end

      context 'when server is running' do
        let(:schema_polling_client) { instance_double(Utils::SchemaPollingClient, start?: true, stop: nil, current_schema: introspection) }
        let(:response) { Utils::SchemaResponse.new(introspection, 'etag123') }
        let(:rpc_client) { instance_double(Utils::RpcClient, fetch_schema: response) }

        before do
          allow(Utils::SchemaPollingClient).to receive(:new).and_return(schema_polling_client)
        end

        it 'build datasource' do
          datasource = described_class.build({ uri: 'http://localhost' })

          expect(datasource).to be_a(ForestAdminDatasourceRpc::Datasource)
        end

        it 'starts schema polling which fetches the initial schema' do
          described_class.build({ uri: 'http://localhost' })

          expect(schema_polling_client).to have_received(:start?)
          expect(schema_polling_client).to have_received(:current_schema)
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
          # Mock schema_polling_client to return introspection with connections
          polling_client_with_connections = instance_double(
            Utils::SchemaPollingClient,
            start?: true,
            stop: nil,
            current_schema: introspection_with_connections
          )
          allow(Utils::SchemaPollingClient).to receive(:new).and_return(polling_client_with_connections)

          datasource = described_class.build({ uri: 'http://localhost' })

          expect(datasource.live_query_connections).to eq({ 'primary' => 'primary', 'secondary' => 'secondary' })
        end

        it 'initializes schema polling client for schema updates' do
          described_class.build({ uri: 'http://localhost' })

          expect(Utils::SchemaPollingClient).to have_received(:new)
          expect(schema_polling_client).to have_received(:start?)
        end
      end

      context 'when server is not running' do
        let(:schema_polling_client) { instance_double(Utils::SchemaPollingClient, start?: true, current_schema: nil) }

        before do
          allow(Utils::SchemaPollingClient).to receive(:new).and_return(schema_polling_client)
        end

        it 'raises exception when schema fetch fails and no introspection provided' do
          expect do
            described_class.build({ uri: 'http://localhost' })
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            /Fatal: Unable to build RPC datasource.*no introspection schema was provided/
          )
        end
      end

      context 'with schema polling interval configuration' do
        let(:response) { Utils::SchemaResponse.new(introspection, 'etag123') }
        let(:rpc_client) { instance_double(Utils::RpcClient, fetch_schema: response) }
        let(:schema_polling_client) { instance_double(Utils::SchemaPollingClient, start?: true, current_schema: introspection) }

        before do
          allow(Utils::RpcClient).to receive(:new).and_return(rpc_client)
          allow(Utils::SchemaPollingClient).to receive(:new).and_return(schema_polling_client)
        end

        it 'uses default interval (600s) when no config provided' do
          described_class.build({ uri: 'http://localhost' })

          expect(Utils::SchemaPollingClient).to have_received(:new).with(
            'http://localhost',
            'secret',
            polling_interval: 600,
            introspection_schema: nil,
            introspection_etag: nil
          )
        end

        it 'uses options[:schema_polling_interval_sec] when provided' do
          described_class.build({ uri: 'http://localhost', schema_polling_interval_sec: 120 })

          expect(Utils::SchemaPollingClient).to have_received(:new).with(
            'http://localhost',
            'secret',
            polling_interval: 120,
            introspection_schema: nil,
            introspection_etag: nil
          )
        end

        it 'uses ENV["SCHEMA_POLLING_INTERVAL_SEC"] when set' do
          ENV['SCHEMA_POLLING_INTERVAL_SEC'] = '30'

          described_class.build({ uri: 'http://localhost' })

          expect(Utils::SchemaPollingClient).to have_received(:new).with(
            'http://localhost',
            'secret',
            polling_interval: 30,
            introspection_schema: nil,
            introspection_etag: nil
          )
        ensure
          ENV.delete('SCHEMA_POLLING_INTERVAL_SEC')
        end

        it 'prioritizes options[:schema_polling_interval_sec] over ENV' do
          ENV['SCHEMA_POLLING_INTERVAL_SEC'] = '30'

          described_class.build({ uri: 'http://localhost', schema_polling_interval_sec: 120 })

          expect(Utils::SchemaPollingClient).to have_received(:new).with(
            'http://localhost',
            'secret',
            polling_interval: 120,
            introspection_schema: nil,
            introspection_etag: nil
          )
        ensure
          ENV.delete('SCHEMA_POLLING_INTERVAL_SEC')
        end

        it 'passes introspection_etag to schema polling client when provided' do
          described_class.build({
                                  uri: 'http://localhost',
                                  introspection: introspection,
                                  introspection_etag: 'precomputed-etag-123'
                                })

          expect(Utils::SchemaPollingClient).to have_received(:new).with(
            'http://localhost',
            'secret',
            polling_interval: 600,
            introspection_schema: introspection,
            introspection_etag: 'precomputed-etag-123'
          )
        end

        it 'passes introspection_schema without etag when only introspection is provided' do
          described_class.build({
                                  uri: 'http://localhost',
                                  introspection: introspection
                                })

          expect(Utils::SchemaPollingClient).to have_received(:new).with(
            'http://localhost',
            'secret',
            polling_interval: 600,
            introspection_schema: introspection,
            introspection_etag: nil
          )
        end
      end
    end
  end
end
