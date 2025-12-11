require 'spec_helper'
require 'json'

module ForestAdminRpcAgent
  describe Agent do
    let(:instance) { described_class.instance }
    let(:logger) { instance_double(ForestAdminAgent::Services::LoggerService) }
    let(:datasource) { instance_double(ForestAdminDatasourceToolkit::Datasource) }

    before do
      allow(logger).to receive(:log)
      allow(ForestAdminRpcAgent::Facades::Container).to receive(:logger).and_return(logger)
    end

    describe '#send_schema' do
      context 'when skip_schema_update is enabled' do
        let(:customizer) { instance_double(ForestAdminDatasourceCustomizer::DatasourceCustomizer) }

        before do
          instance.container.register(:datasource, datasource, replace: true)
          allow(instance).to receive(:customizer).and_return(customizer)
          allow(customizer).to receive(:schema).and_return({})
          allow(datasource).to receive_messages(collections: {}, live_query_connections: {})
          allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive_messages(generate: [], meta: {})
        end

        it 'does not generate schema and logs skip message' do
          allow(ForestAdminRpcAgent::Facades::Container).to receive(:cache) do |key|
            case key
            when :skip_schema_update then true
            when :is_production then false
            end
          end

          instance.send_schema

          expect(logger).to have_received(:log)
            .with('Warn', '[ForestAdmin] Schema update skipped (skip_schema_update flag is true)')
        end

        it 'generates schema when force flag is true despite skip setting' do
          allow(ForestAdminRpcAgent::Facades::Container).to receive(:cache) do |key|
            case key
            when :skip_schema_update then true
            when :schema_path then '/tmp/test-schema.json'
            when :is_production then false
            end
          end
          allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive_messages(generate: [], meta: {})
          allow(File).to receive(:write)

          instance.send_schema(force: true)

          expect(logger).not_to have_received(:log).with('Warn', include('skipped'))
          expect(File).to have_received(:write).with('/tmp/test-schema.json', anything)
        end
      end

      context 'when in production mode' do
        let(:customizer) { instance_double(ForestAdminDatasourceCustomizer::DatasourceCustomizer) }

        before do
          instance.container.register(:datasource, datasource, replace: true)
          allow(instance).to receive(:customizer).and_return(customizer)
          allow(customizer).to receive(:schema).and_return({})
          allow(datasource).to receive_messages(collections: {}, live_query_connections: {})
        end

        it 'does not write schema file but computes schema from datasource' do
          allow(ForestAdminRpcAgent::Facades::Container).to receive(:cache) do |key|
            case key
            when :skip_schema_update then false
            when :schema_path then '/path/to/schema.json'
            when :is_production then true
            end
          end
          allow(File).to receive(:write)

          instance.send_schema

          expect(File).not_to have_received(:write)
          expect(instance.cached_schema).not_to be_nil
          expect(logger).to have_received(:log)
            .with('Info', 'RPC agent schema computed from datasource and cached.')
        end
      end

      context 'when in development mode' do
        let(:customizer) { instance_double(ForestAdminDatasourceCustomizer::DatasourceCustomizer) }

        before do
          instance.container.register(:datasource, datasource, replace: true)
          allow(instance).to receive(:customizer).and_return(customizer)
          allow(customizer).to receive(:schema).and_return({})
          allow(datasource).to receive_messages(collections: {}, live_query_connections: {})
        end

        it 'generates and writes schema to file' do
          allow(ForestAdminRpcAgent::Facades::Container).to receive(:cache) do |key|
            { skip_schema_update: false, schema_path: '/tmp/test-schema.json', is_production: false }[key]
          end
          allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive_messages(generate: [], meta: {})
          allow(File).to receive(:write)

          instance.send_schema

          expect(File).to have_received(:write).with('/tmp/test-schema.json', anything)
          expect(logger).to have_received(:log).with('Info',
                                                     'RPC agent schema file saved to /tmp/test-schema.json')
        end

        it 'formats schema JSON correctly with RPC schema structure' do
          allow(ForestAdminRpcAgent::Facades::Container).to receive(:cache) do |key|
            { skip_schema_update: false, schema_path: '/tmp/test-schema.json', is_production: false }[key]
          end

          test_collection = instance_double(Collection)
          allow(test_collection).to receive_messages(name: 'Test', schema: { fields: {} })
          allow(datasource).to receive_messages(
            collections: { 'Test' => test_collection },
            live_query_connections: { 'main' => {} }
          )

          written_content = nil
          allow(File).to receive(:write) { |_path, content| written_content = content }

          instance.send_schema

          parsed = JSON.parse(written_content, symbolize_names: true)
          # RPC schema format includes collections with full schemas and native_query_connections
          expect(parsed[:collections]).to eq([{ fields: {}, name: 'Test' }])
          expect(parsed[:native_query_connections]).to eq([{ name: 'main' }])
        end

        it 'caches the schema and computes hash' do
          allow(ForestAdminRpcAgent::Facades::Container).to receive(:cache) do |key|
            { skip_schema_update: false, schema_path: '/tmp/test-schema.json', is_production: false }[key]
          end
          allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive_messages(generate: [{ name: 'Test' }],
                                                                                    meta: {})
          allow(File).to receive(:write)

          instance.send_schema

          expect(instance.cached_schema).not_to be_nil
          expect(instance.cached_schema_hash).not_to be_nil
          expect(instance.cached_schema_hash).to be_a(String)
          expect(instance.cached_schema_hash.length).to eq(40) # SHA1 hex length
        end
      end

      context 'when it never sends schema to Forest Admin servers' do
        let(:customizer) { instance_double(ForestAdminDatasourceCustomizer::DatasourceCustomizer) }

        before do
          instance.container.register(:datasource, datasource, replace: true)
          allow(instance).to receive(:customizer).and_return(customizer)
          allow(customizer).to receive(:schema).and_return({})
          allow(datasource).to receive_messages(collections: {}, live_query_connections: {})
        end

        it 'logs that schema is not sent to servers' do
          allow(ForestAdminRpcAgent::Facades::Container).to receive(:cache) do |key|
            { skip_schema_update: false, schema_path: '/tmp/test-schema.json', is_production: false }[key]
          end
          allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive_messages(generate: [], meta: {})
          allow(File).to receive(:write)

          instance.send_schema

          expect(logger).to have_received(:log).with('Info', 'RPC agent does not send schema to Forest Admin servers.')
        end

        it 'does not make HTTP requests to Forest Admin' do
          allow(ForestAdminRpcAgent::Facades::Container).to receive(:cache) do |key|
            { skip_schema_update: false, schema_path: '/tmp/test-schema.json', is_production: false }[key]
          end
          allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive_messages(generate: [], meta: {})
          allow(File).to receive(:write)
          allow(ForestAdminAgent::Http::ForestAdminApiRequester).to receive(:new)

          instance.send_schema

          # Ensure no HTTP calls are made
          expect(ForestAdminAgent::Http::ForestAdminApiRequester).not_to have_received(:new)
        end
      end
    end

    describe '#mark_collections_as_rpc' do
      it 'adds collection names to rpc_collections' do
        instance.mark_collections_as_rpc('users', 'orders')

        expect(instance.rpc_collections).to include('users', 'orders')
      end

      it 'returns self for method chaining' do
        result = instance.mark_collections_as_rpc('products')

        expect(result).to eq(instance)
      end
    end
  end
end
