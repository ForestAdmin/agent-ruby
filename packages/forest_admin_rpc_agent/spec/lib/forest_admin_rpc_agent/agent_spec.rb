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

          test_collection = instance_double(ForestAdminDatasourceToolkit::Collection)
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

      it 'accepts regex patterns' do
        instance.mark_collections_as_rpc(/^rpc_/, /.*_private$/)

        expect(instance.rpc_collections).to include(/^rpc_/, /.*_private$/)
      end

      it 'accepts mixed strings and regex patterns' do
        instance.mark_collections_as_rpc('users', /^admin_/)

        expect(instance.rpc_collections).to include('users', /^admin_/)
      end

      it 'returns self for method chaining' do
        result = instance.mark_collections_as_rpc('products')

        expect(result).to eq(instance)
      end
    end

    describe '#schema_hash_matches?' do
      let(:customizer) { instance_double(ForestAdminDatasourceCustomizer::DatasourceCustomizer) }

      before do
        instance.container.register(:datasource, datasource, replace: true)
        allow(instance).to receive(:customizer).and_return(customizer)
        allow(customizer).to receive(:schema).and_return({})
        allow(datasource).to receive_messages(collections: {}, live_query_connections: {})
        allow(ForestAdminRpcAgent::Facades::Container).to receive(:cache) do |key|
          { skip_schema_update: false, schema_path: '/tmp/test-schema.json', is_production: true }[key]
        end
      end

      it 'returns false when cached_schema_hash is nil' do
        expect(instance.schema_hash_matches?('some_hash')).to be false
      end

      it 'returns false when provided_hash is nil' do
        instance.send_schema
        expect(instance.schema_hash_matches?(nil)).to be false
      end

      it 'returns true when hashes match' do
        instance.send_schema
        cached_hash = instance.cached_schema_hash

        expect(instance.schema_hash_matches?(cached_hash)).to be true
      end

      it 'returns false when hashes do not match' do
        instance.send_schema

        expect(instance.schema_hash_matches?('wrong_hash')).to be false
      end
    end

    describe '#build_rpc_schema_from_datasource' do
      let(:customizer) { instance_double(ForestAdminDatasourceCustomizer::DatasourceCustomizer) }

      before do
        instance.container.register(:datasource, datasource, replace: true)
        allow(instance).to receive(:customizer).and_return(customizer)
        allow(customizer).to receive(:schema).and_return({})
        allow(ForestAdminRpcAgent::Facades::Container).to receive(:cache) do |key|
          { skip_schema_update: false, schema_path: '/tmp/test-schema.json', is_production: true }[key]
        end
      end

      it 'excludes RPC collections from schema collections' do
        rpc_collection = instance_double(ForestAdminDatasourceToolkit::Collection)
        normal_collection = instance_double(ForestAdminDatasourceToolkit::Collection)

        allow(rpc_collection).to receive_messages(name: 'RpcCollection', schema: { fields: {} })
        allow(normal_collection).to receive_messages(name: 'NormalCollection', schema: { fields: {} })
        allow(datasource).to receive_messages(
          collections: { 'RpcCollection' => rpc_collection, 'NormalCollection' => normal_collection },
          live_query_connections: {}
        )

        instance.mark_collections_as_rpc('RpcCollection')
        instance.send_schema

        collection_names = instance.cached_schema[:collections].map { |c| c[:name] }
        expect(collection_names).to include('NormalCollection')
        expect(collection_names).not_to include('RpcCollection')
      end

      it 'excludes collections matching regex patterns from schema collections' do
        rpc_collection1 = instance_double(ForestAdminDatasourceToolkit::Collection)
        rpc_collection2 = instance_double(ForestAdminDatasourceToolkit::Collection)
        normal_collection = instance_double(ForestAdminDatasourceToolkit::Collection)

        allow(rpc_collection1).to receive_messages(name: 'rpc_users', schema: { fields: {} })
        allow(rpc_collection2).to receive_messages(name: 'rpc_orders', schema: { fields: {} })
        allow(normal_collection).to receive_messages(name: 'products', schema: { fields: {} })
        allow(datasource).to receive_messages(
          collections: {
            'rpc_users' => rpc_collection1,
            'rpc_orders' => rpc_collection2,
            'products' => normal_collection
          },
          live_query_connections: {}
        )

        instance.mark_collections_as_rpc(/^rpc_/)
        instance.send_schema

        collection_names = instance.cached_schema[:collections].map { |c| c[:name] }
        expect(collection_names).to include('products')
        expect(collection_names).not_to include('rpc_users', 'rpc_orders')
      end

      it 'extracts relations from RPC collections to non-RPC collections into rpc_relations' do
        rpc_collection = instance_double(ForestAdminDatasourceToolkit::Collection)
        normal_collection = instance_double(ForestAdminDatasourceToolkit::Collection)

        relation_field = instance_double(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
        allow(relation_field).to receive_messages(
          type: 'ManyToOne',
          foreign_collection: 'NormalCollection'
        )

        allow(rpc_collection).to receive_messages(
          name: 'RpcCollection',
          schema: { fields: { 'normal' => relation_field } }
        )
        allow(normal_collection).to receive_messages(name: 'NormalCollection', schema: { fields: {} })
        allow(datasource).to receive_messages(
          collections: { 'RpcCollection' => rpc_collection, 'NormalCollection' => normal_collection },
          live_query_connections: {}
        )

        instance.mark_collections_as_rpc('RpcCollection')
        instance.send_schema

        expect(instance.cached_schema[:rpc_relations]).to have_key('RpcCollection')
        expect(instance.cached_schema[:rpc_relations]['RpcCollection']).to have_key('normal')
      end

      it 'extracts relations from normal collections to RPC collections into rpc_relations' do
        rpc_collection = instance_double(ForestAdminDatasourceToolkit::Collection)
        normal_collection = instance_double(ForestAdminDatasourceToolkit::Collection)

        relation_field = instance_double(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
        allow(relation_field).to receive_messages(
          type: 'ManyToOne',
          foreign_collection: 'RpcCollection'
        )

        allow(rpc_collection).to receive_messages(name: 'RpcCollection', schema: { fields: {} })
        allow(normal_collection).to receive_messages(
          name: 'NormalCollection',
          schema: { fields: { 'rpc_ref' => relation_field } }
        )
        allow(datasource).to receive_messages(
          collections: { 'RpcCollection' => rpc_collection, 'NormalCollection' => normal_collection },
          live_query_connections: {}
        )

        instance.mark_collections_as_rpc('RpcCollection')
        instance.send_schema

        expect(instance.cached_schema[:rpc_relations]).to have_key('NormalCollection')
        expect(instance.cached_schema[:rpc_relations]['NormalCollection']).to have_key('rpc_ref')
      end

      it 'does not extract relations between RPC collections' do
        rpc_collection1 = instance_double(ForestAdminDatasourceToolkit::Collection)
        rpc_collection2 = instance_double(ForestAdminDatasourceToolkit::Collection)

        relation_field = instance_double(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
        allow(relation_field).to receive_messages(
          type: 'ManyToOne',
          foreign_collection: 'RpcCollection2'
        )

        allow(rpc_collection1).to receive_messages(
          name: 'RpcCollection1',
          schema: { fields: { 'other_rpc' => relation_field } }
        )
        allow(rpc_collection2).to receive_messages(name: 'RpcCollection2', schema: { fields: {} })
        allow(datasource).to receive_messages(
          collections: { 'RpcCollection1' => rpc_collection1, 'RpcCollection2' => rpc_collection2 },
          live_query_connections: {}
        )

        instance.mark_collections_as_rpc('RpcCollection1', 'RpcCollection2')
        instance.send_schema

        rpc_relations_for_rpc1 = instance.cached_schema[:rpc_relations]['RpcCollection1'] || {}
        expect(rpc_relations_for_rpc1).not_to have_key('other_rpc')
      end

      it 'sorts filter_operators for Column fields' do
        normal_collection = instance_double(ForestAdminDatasourceToolkit::Collection)
        column_field = instance_double(ForestAdminDatasourceToolkit::Schema::ColumnSchema)

        allow(column_field).to receive_messages(type: 'Column')
        allow(column_field).to receive(:filter_operators=)
        allow(column_field).to receive(:filter_operators).and_return(%w[equal greater_than less_than])
        allow(ForestAdminAgent::Utils::Schema::FrontendFilterable).to receive(:sort_operators)
          .and_return(%w[equal greater_than less_than])

        allow(normal_collection).to receive_messages(
          name: 'NormalCollection',
          schema: { fields: { 'id' => column_field } }
        )
        allow(datasource).to receive_messages(
          collections: { 'NormalCollection' => normal_collection },
          live_query_connections: {}
        )

        instance.send_schema

        expect(ForestAdminAgent::Utils::Schema::FrontendFilterable).to have_received(:sort_operators)
      end

      it 'includes native_query_connections in schema' do
        normal_collection = instance_double(ForestAdminDatasourceToolkit::Collection)
        allow(normal_collection).to receive_messages(name: 'NormalCollection', schema: { fields: {} })
        allow(datasource).to receive_messages(
          collections: { 'NormalCollection' => normal_collection },
          live_query_connections: { 'main' => {}, 'secondary' => {} }
        )

        instance.send_schema

        expect(instance.cached_schema[:native_query_connections]).to contain_exactly(
          { name: 'main' },
          { name: 'secondary' }
        )
      end
    end
  end
end
