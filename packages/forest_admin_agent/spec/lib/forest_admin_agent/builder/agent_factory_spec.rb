require 'spec_helper'
require 'digest/sha1'
require 'json'

module ForestAdminAgent
  module Builder
    describe AgentFactory do
      context 'with agent setup' do
        describe 'setup' do
          it 'set @has_env_secret to true when env_secret exist' do
            expect(described_class.instance.has_env_secret).to be true
          end

          it 'build the container' do
            expect(described_class.instance.container).not_to be_nil
          end

          it 'build the cache' do
            expect(described_class.instance.container.resolve(:cache)).not_to be_nil
            expect(described_class.instance.container.resolve(:cache)).to be_instance_of FileCache
          end

          it 'build the logger' do
            expect(described_class.instance.container.resolve(:logger)).not_to be_nil
            expect(described_class.instance.container.resolve(:logger)).to be_instance_of Services::LoggerService
          end
        end

        describe 'add_datasource' do
          it 'add collections to the customizer datasource' do
            datasource = ForestAdminDatasourceToolkit::Datasource.new
            collection_book = ForestAdminDatasourceToolkit::Collection.new(datasource, 'Book')
            datasource.add_collection(collection_book)
            described_class.instance.add_datasource(datasource)
            described_class.instance.customizer.datasource({})

            expect(described_class.instance.customizer.collections.size).to eq(1)
            expect(described_class.instance.customizer.get_collection('Book').name).to eq('Book')
          end
        end

        describe 'build' do
          it 'add datasource to the container' do
            allow(described_class.instance).to receive(:send_schema)
            described_class.instance.build

            expect(described_class.instance.container.resolve(:datasource))
              .to eq(described_class.instance.customizer.datasource({}))
          end
        end

        describe 'reload!' do
          it 'reloads the customizer' do
            instance = described_class.instance
            allow(instance).to receive(:send_schema)
            allow(instance.customizer).to receive(:reload!)
            instance.reload!

            expect(instance.customizer).to have_received(:reload!)
          end

          it 'add datasource to the container' do
            allow(described_class.instance).to receive(:send_schema)
            described_class.instance.reload!

            expect(described_class.instance.container.resolve(:datasource))
              .to eq(described_class.instance.customizer.datasource({}))
          end

          it 'logs an error and does not register the datasource if reload! raises' do
            instance = described_class.instance

            logger = instance_spy(Services::LoggerService)
            instance.instance_variable_set(:@logger, logger)

            allow(instance.customizer).to receive(:reload!).and_raise(StandardError.new('Foo'))
            allow(instance).to receive(:send_schema)
            allow(instance.container).to receive(:register)

            instance.reload!

            expect(logger).to have_received(:log).with('Error', 'Error reloading agent: Foo')
            expect(instance.container).not_to have_received(:register)
            expect(instance).not_to have_received(:send_schema)
          end
        end

        describe 'send_schema' do
          it 'do nothing if env_secret is nil' do
            described_class.instance.instance_variable_set(:@has_env_secret, false)
            allow(Facades::Container).to receive(:cache).with(:skip_schema_update).and_return(false)
            allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive(:serialize)
            described_class.instance.build

            expect(ForestAdminAgent::Utils::Schema::SchemaEmitter).not_to have_received(:serialize)
          end

          it 'raises error in production if schema file does not exist' do
            instance = described_class.instance
            instance.instance_variable_set(:@has_env_secret, true)
            allow(Facades::Container).to receive(:cache).with(:skip_schema_update).and_return(false)
            allow(Facades::Container).to receive(:cache).with(:schema_path).and_return('/path/to/schema.json')
            allow(Facades::Container).to receive(:cache).with(:is_production).and_return(true)
            allow(File).to receive(:exist?).with('/path/to/schema.json').and_return(false)

            expect { instance.send_schema }.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException)
          end

          it 'loads schema from file in production mode' do
            instance = described_class.instance
            instance.instance_variable_set(:@has_env_secret, true)
            schema_content = { meta: {}, collections: [] }.to_json

            allow(Facades::Container).to receive(:cache).with(:skip_schema_update).and_return(false)
            allow(Facades::Container).to receive(:cache).with(:schema_path).and_return('/path/to/schema.json')
            allow(Facades::Container).to receive(:cache).with(:is_production).and_return(true)
            allow(Facades::Container).to receive(:cache).with(:append_schema_path).and_return(nil)
            allow(File).to receive(:exist?).with('/path/to/schema.json').and_return(true)
            allow(File).to receive(:read).with('/path/to/schema.json').and_return(schema_content)
            allow(instance).to receive(:post_schema)

            instance.send_schema

            expect(instance).to have_received(:post_schema)
          end

          it 'generates and writes schema in non-production mode' do
            instance = described_class.instance
            instance.instance_variable_set(:@has_env_secret, true)

            datasource = instance_double(ForestAdminDatasourceToolkit::Datasource)
            instance.container.register(:datasource, datasource)

            allow(Facades::Container).to receive(:cache).with(:skip_schema_update).and_return(false)
            allow(Facades::Container).to receive(:cache).with(:schema_path).and_return('/path/to/schema.json')
            allow(Facades::Container).to receive(:cache).with(:is_production).and_return(false)
            allow(Facades::Container).to receive(:cache).with(:append_schema_path).and_return(nil)
            allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive_messages(generate: [], meta: {})
            allow(File).to receive(:write)
            allow(instance).to receive(:post_schema)

            instance.send_schema

            expect(File).to have_received(:write).with('/path/to/schema.json', anything)
            expect(instance).to have_received(:post_schema)
          end

          it 'merges append_schema when provided' do
            instance = described_class.instance
            instance.instance_variable_set(:@has_env_secret, true)
            append_schema = { collections: [{ name: 'Extra' }] }.to_json

            datasource = instance_double(ForestAdminDatasourceToolkit::Datasource)
            instance.container.register(:datasource, datasource)

            allow(Facades::Container).to receive(:cache).with(:skip_schema_update).and_return(false)
            allow(Facades::Container).to receive(:cache).with(:schema_path).and_return('/path/to/schema.json')
            allow(Facades::Container).to receive(:cache).with(:is_production).and_return(false)
            allow(Facades::Container).to receive(:cache).with(:append_schema_path).and_return('/path/to/append.json')
            allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive_messages(generate: [{ name: 'Main' }], meta: {})
            allow(File).to receive(:write)
            allow(File).to receive(:read).with('/path/to/append.json').and_return(append_schema)
            allow(instance).to receive(:post_schema)

            instance.send_schema

            expect(instance).to have_received(:post_schema).with(hash_including(collections: [{ name: 'Main' }, { name: 'Extra' }]), anything)
          end

          it 'raises error if append_schema file cannot be loaded' do
            instance = described_class.instance
            instance.instance_variable_set(:@has_env_secret, true)

            datasource = instance_double(ForestAdminDatasourceToolkit::Datasource)
            instance.container.register(:datasource, datasource)

            allow(Facades::Container).to receive(:cache).with(:skip_schema_update).and_return(false)
            allow(Facades::Container).to receive(:cache).with(:schema_path).and_return('/path/to/schema.json')
            allow(Facades::Container).to receive(:cache).with(:is_production).and_return(false)
            allow(Facades::Container).to receive(:cache).with(:append_schema_path).and_return('/path/to/append.json')
            allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive_messages(generate: [], meta: {})
            allow(File).to receive(:write)
            allow(File).to receive(:read).with('/path/to/append.json').and_raise(Errno::ENOENT)

            expect { instance.send_schema }.to raise_error(/Can't load additional schema/)
          end

          context 'with skip_schema_update enabled' do
            it 'does not send schema and logs skip message' do
              instance = described_class.instance
              instance.instance_variable_set(:@has_env_secret, true)
              logger = instance_spy(Services::LoggerService)
              instance.instance_variable_set(:@logger, logger)

              allow(Facades::Container).to receive(:cache).with(:skip_schema_update).and_return(true)
              allow(Facades::Container).to receive(:cache).with(:is_production).and_return(false)
              allow(instance).to receive(:post_schema)

              instance.send_schema

              expect(logger).to have_received(:log).with('Warn', '[ForestAdmin] Schema update skipped (skip_schema_update flag is true)')
              expect(instance).not_to have_received(:post_schema)
            end

            it 'logs the environment mode when skipping' do
              instance = described_class.instance
              instance.instance_variable_set(:@has_env_secret, true)
              logger = instance_spy(Services::LoggerService)
              instance.instance_variable_set(:@logger, logger)

              allow(Facades::Container).to receive(:cache).with(:skip_schema_update).and_return(true)
              allow(Facades::Container).to receive(:cache).with(:is_production).and_return(true)

              instance.send_schema

              expect(logger).to have_received(:log).with('Info', '[ForestAdmin] Running in production mode')
            end

            it 'sends schema when force flag is true despite skip setting' do
              instance = described_class.instance
              instance.instance_variable_set(:@has_env_secret, true)
              logger = instance_spy(Services::LoggerService)
              instance.instance_variable_set(:@logger, logger)

              datasource = instance_double(ForestAdminDatasourceToolkit::Datasource)
              instance.container.register(:datasource, datasource)

              allow(Facades::Container).to receive(:cache).with(:skip_schema_update).and_return(true)
              allow(Facades::Container).to receive(:cache).with(:schema_path).and_return('/path/to/schema.json')
              allow(Facades::Container).to receive(:cache).with(:is_production).and_return(false)
              allow(Facades::Container).to receive(:cache).with(:append_schema_path).and_return(nil)
              allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive_messages(generate: [], meta: {})
              allow(File).to receive(:write)
              allow(instance).to receive(:post_schema)

              instance.send_schema(force: true)

              expect(logger).not_to have_received(:log).with('Warn', include('skipped'))
              expect(instance).to have_received(:post_schema)
            end
          end

          context 'with skip_schema_update disabled (default)' do
            it 'sends schema normally' do
              instance = described_class.instance
              instance.instance_variable_set(:@has_env_secret, true)
              logger = instance_spy(Services::LoggerService)
              instance.instance_variable_set(:@logger, logger)

              datasource = instance_double(ForestAdminDatasourceToolkit::Datasource)
              instance.container.register(:datasource, datasource)

              allow(Facades::Container).to receive(:cache).with(:skip_schema_update).and_return(false)
              allow(Facades::Container).to receive(:cache).with(:schema_path).and_return('/path/to/schema.json')
              allow(Facades::Container).to receive(:cache).with(:is_production).and_return(false)
              allow(Facades::Container).to receive(:cache).with(:append_schema_path).and_return(nil)
              allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive_messages(generate: [], meta: {})
              allow(File).to receive(:write)
              allow(instance).to receive(:post_schema)

              instance.send_schema

              expect(logger).not_to have_received(:log).with('Warn', include('skipped'))
              expect(instance).to have_received(:post_schema)
            end
          end
        end

        describe 'remove_collection' do
          it 'removes collections from customizer' do
            instance = described_class.instance
            allow(instance.customizer).to receive(:remove_collection)

            instance.remove_collection(['Book'])

            expect(instance.customizer).to have_received(:remove_collection).with(['Book'])
          end
        end

        describe 'add_chart' do
          it 'adds chart to customizer and returns self' do
            instance = described_class.instance
            allow(instance.customizer).to receive(:add_chart)
            block = proc {}

            result = instance.add_chart('MyChart', &block)

            expect(instance.customizer).to have_received(:add_chart).with('MyChart')
            expect(result).to eq(instance)
          end
        end

        describe 'customize_collection' do
          it 'customizes collection and returns self' do
            instance = described_class.instance
            allow(instance.customizer).to receive(:customize_collection)
            handler = proc {}

            result = instance.customize_collection('Book', &handler)

            expect(instance.customizer).to have_received(:customize_collection).with('Book', handler)
            expect(result).to eq(instance)
          end
        end
      end
    end
  end
end
