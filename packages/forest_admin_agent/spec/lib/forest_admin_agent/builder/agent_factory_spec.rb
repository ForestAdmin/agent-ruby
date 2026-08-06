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

          it 'build the config' do
            expect(described_class.instance.container.resolve(:config)).not_to be_nil
            expect(described_class.instance.container.resolve(:config)).to be_instance_of Hash
          end

          it 'build the logger' do
            expect(described_class.instance.container.resolve(:logger)).not_to be_nil
            expect(described_class.instance.container.resolve(:logger)).to be_instance_of Services::LoggerService
          end

          context 'when env_secret key is present but nil (e.g. an unconfigured sibling agent, like ' \
                  'ForestAdminRpcAgent bundled but never set up)' do
            it 'sets @has_env_secret to false and skips validation entirely, without warning or raising' do
              instance = described_class.instance
              logger = instance_spy(Services::LoggerService)
              allow(Services::LoggerService).to receive(:new).and_return(logger)
              allow(Facades::Container).to receive(:cache).with(:skip_schema_update).and_return(false)

              expect do
                instance.setup(auth_secret: nil, env_secret: nil, is_production: true)
              end.not_to raise_error

              expect(instance.has_env_secret).to be false

              instance.send_schema

              expect(logger).not_to have_received(:log).with('Warn', anything)
            end
          end

          context 'with schema_only_mode enabled (offline schema generation, e.g. ' \
                  'rake forest_admin:schema:generate)' do
            it 'never validates secrets, even a malformed env_secret in production' do
              instance = described_class.instance

              expect do
                instance.setup(
                  auth_secret: 'cba803d01a4d43b55010cab41fa1ea1f1f51a95e',
                  env_secret: 'not-a-valid-secret',
                  is_production: true
                )
              end.not_to raise_error

              instance.schema_only_mode = true
              allow(instance).to receive(:generate_schema_only)

              expect { instance.build }.not_to raise_error
              expect(instance).to have_received(:generate_schema_only)
            ensure
              instance.schema_only_mode = false
            end
          end
        end

        context 'when env_secret is present but malformed' do
          let(:instance) { described_class.instance }
          let(:valid_options) do
            {
              auth_secret: 'cba803d01a4d43b55010cab41fa1ea1f1f51a95e',
              env_secret: '89719c6d8e2e2de2694c2f220fe2dbf02d5289487364daf1e4c6b13733ed0cdb',
              skip_schema_update: false,
              append_schema_path: nil
            }
          end

          context 'when running in production' do
            let(:prod_options) { valid_options.merge(is_production: true) }

            it 'raises a ValidationError when env_secret is too short' do
              instance.setup(prod_options.merge(env_secret: 'abc123'))

              expect { instance.send_schema }.to raise_error(
                ForestAdminAgent::Http::Exceptions::ValidationError, /config\.env_secret is invalid/
              )
            end

            it 'raises a ValidationError when env_secret contains the variable name (a common copy-paste mistake)' do
              instance.setup(prod_options.merge(env_secret: "FOREST_ENV_SECRET=#{valid_options[:env_secret]}"))

              expect { instance.send_schema }.to raise_error(
                ForestAdminAgent::Http::Exceptions::ValidationError, /config\.env_secret is invalid/
              )
            end

            it 'raises a ValidationError when env_secret has uppercase characters' do
              instance.setup(prod_options.merge(env_secret: valid_options[:env_secret].upcase))

              expect { instance.send_schema }.to raise_error(
                ForestAdminAgent::Http::Exceptions::ValidationError, /config\.env_secret is invalid/
              )
            end

            it 'raises a ValidationError when auth_secret is not a string' do
              instance.setup(prod_options.merge(auth_secret: 42))

              expect { instance.send_schema }.to raise_error(
                ForestAdminAgent::Http::Exceptions::ValidationError, /config\.auth_secret is invalid/
              )
            end

            it 'does not raise when both secrets are well-formed' do
              instance.setup(prod_options)
              allow(instance).to receive_messages(generate_schema_file: { meta: {}, collections: [] }, post_schema: nil)

              expect { instance.send_schema }.not_to raise_error
            end
          end

          context 'when running outside production' do
            let(:dev_options) { valid_options.merge(is_production: false) }

            it 'does not raise, warns instead, and skips the schema sync' do
              logger = instance_spy(Services::LoggerService)
              allow(Services::LoggerService).to receive(:new).and_return(logger)
              instance.setup(dev_options.merge(env_secret: 'abc123'))
              allow(instance).to receive(:generate_schema_file)

              expect { instance.send_schema }.not_to raise_error

              expect(logger).to have_received(:log).with('Warn', /config\.env_secret is invalid/)
              expect(logger).to have_received(:log).with('Warn', /Skipping schema sync/)
              expect(instance).not_to have_received(:generate_schema_file)
            end

            it 'does not raise and does not warn when both secrets are well-formed' do
              logger = instance_spy(Services::LoggerService)
              allow(Services::LoggerService).to receive(:new).and_return(logger)
              instance.setup(dev_options)
              allow(instance).to receive_messages(generate_schema_file: { meta: {}, collections: [] }, post_schema: nil)

              expect { instance.send_schema }.not_to raise_error

              expect(logger).not_to have_received(:log).with('Warn', /is invalid/)
            end
          end
        end

        context 'when the secret is well-formed but rejected by the server' do
          let(:instance) { described_class.instance }
          let(:valid_options) do
            {
              auth_secret: 'cba803d01a4d43b55010cab41fa1ea1f1f51a95e',
              env_secret: '89719c6d8e2e2de2694c2f220fe2dbf02d5289487364daf1e4c6b13733ed0cdb',
              skip_schema_update: false
            }
          end
          let(:not_found_error) do
            ForestAdminAgent::Http::Exceptions::NotFoundError.new(
              'ForestAdmin server failed to find the project related to the envSecret you configured.'
            )
          end

          context 'when running in production' do
            it 'raises the error the server returned' do
              instance.setup(valid_options.merge(is_production: true))
              allow(instance).to receive(:generate_schema_file).and_raise(not_found_error)

              expect { instance.send_schema }.to raise_error(ForestAdminAgent::Http::Exceptions::NotFoundError)
            end
          end

          context 'when running outside production' do
            it 'does not raise, warns instead, and continues without the schema' do
              logger = instance_spy(Services::LoggerService)
              allow(Services::LoggerService).to receive(:new).and_return(logger)
              instance.setup(valid_options.merge(is_production: false))
              allow(instance).to receive(:generate_schema_file).and_raise(not_found_error)

              expect { instance.send_schema }.not_to raise_error

              expect(logger).to have_received(:log).with('Warn', /failed to find the project/)
              expect(logger).to have_received(:log).with('Warn', /Schema sync failed/)
            end
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

          it 'calls send_schema when schema_only_mode is false' do
            instance = described_class.instance
            instance.schema_only_mode = false
            allow(instance).to receive(:send_schema)

            instance.build

            expect(instance).to have_received(:send_schema)
          end

          it 'calls generate_schema_only when schema_only_mode is true' do
            instance = described_class.instance
            instance.schema_only_mode = true
            allow(instance).to receive(:generate_schema_only)

            instance.build

            expect(instance).to have_received(:generate_schema_only)
          ensure
            instance.schema_only_mode = false
          end
        end

        describe 'generate_schema_only' do
          it 'generates schema and writes to default path' do
            instance = described_class.instance
            logger = instance_spy(Services::LoggerService)
            instance.instance_variable_set(:@logger, logger)

            datasource = instance_double(ForestAdminDatasourceToolkit::Datasource)
            instance.container.register(:datasource, datasource)

            allow(Facades::Container).to receive(:cache).with(:schema_path).and_return('/path/to/schema.json')
            allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive_messages(generate: [], meta: {})
            allow(File).to receive(:write)

            instance.generate_schema_only

            expect(File).to have_received(:write).with('/path/to/schema.json', anything)
            expect(logger).to have_received(:log).with('Info', '[ForestAdmin] Schema generated successfully at /path/to/schema.json')
          end

          it 'returns the generated schema' do
            instance = described_class.instance
            logger = instance_spy(Services::LoggerService)
            instance.instance_variable_set(:@logger, logger)

            datasource = instance_double(ForestAdminDatasourceToolkit::Datasource)
            instance.container.register(:datasource, datasource)

            allow(Facades::Container).to receive(:cache).with(:schema_path).and_return('/path/to/schema.json')
            allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive_messages(generate: [{ name: 'Book' }], meta: { liana: 'forest-rails' })
            allow(File).to receive(:write)

            result = instance.generate_schema_only

            expect(result).to eq({ meta: { liana: 'forest-rails' }, collections: [{ name: 'Book' }] })
          end

          it 'does not call post_schema' do
            instance = described_class.instance
            logger = instance_spy(Services::LoggerService)
            instance.instance_variable_set(:@logger, logger)

            datasource = instance_double(ForestAdminDatasourceToolkit::Datasource)
            instance.container.register(:datasource, datasource)

            allow(Facades::Container).to receive(:cache).with(:schema_path).and_return('/path/to/schema.json')
            allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive_messages(generate: [], meta: {})
            allow(File).to receive(:write)
            allow(instance).to receive(:post_schema)

            instance.generate_schema_only

            expect(instance).not_to have_received(:post_schema)
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

          it 'resets the serializer primary-key cache' do
            instance = described_class.instance
            allow(instance).to receive(:send_schema)
            allow(instance.customizer).to receive(:reload!)
            allow(ForestAdminAgent::Serializer::ForestSerializer).to receive(:reset_cache!)

            instance.reload!

            expect(ForestAdminAgent::Serializer::ForestSerializer).to have_received(:reset_cache!)
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

          it 'skips reload if another reload is already in progress' do
            instance = described_class.instance

            logger = instance_spy(Services::LoggerService)
            instance.instance_variable_set(:@logger, logger)

            # Simulate a long-running reload by blocking inside customizer.reload!
            reload_started = Queue.new
            proceed = Queue.new

            allow(instance.customizer).to receive(:reload!) do
              reload_started << true
              proceed.pop
            end
            allow(instance).to receive(:send_schema)

            first_thread = Thread.new { instance.reload! }
            reload_started.pop # wait until the first reload is inside customizer.reload!

            # Second reload should be skipped
            instance.reload!

            expect(logger).to have_received(:log).with('Info', 'Agent is already reloading. Do nothing.')

            proceed << true # unblock first reload
            first_thread.join
          end

          it 'allows a new reload after the previous one completes' do
            instance = described_class.instance

            allow(instance.customizer).to receive(:reload!)
            allow(instance).to receive(:send_schema)

            instance.reload!
            instance.reload!

            expect(instance.customizer).to have_received(:reload!).twice
          end

          it 'resets the reloading flag even when an error occurs' do
            instance = described_class.instance

            logger = instance_spy(Services::LoggerService)
            instance.instance_variable_set(:@logger, logger)

            allow(instance.customizer).to receive(:reload!).and_raise(StandardError.new('Boom'))
            allow(instance).to receive(:send_schema)

            instance.reload!

            # Should allow a subsequent reload (flag was reset despite the error)
            allow(instance.customizer).to receive(:reload!)
            instance.reload!

            expect(instance.customizer).to have_received(:reload!).twice
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

            expect { instance.send_schema }.to raise_error(ForestAdminAgent::Http::Exceptions::InternalServerError)
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

          it 'raises error if append_schema file cannot be loaded, in production' do
            instance = described_class.instance
            instance.instance_variable_set(:@has_env_secret, true)

            datasource = instance_double(ForestAdminDatasourceToolkit::Datasource)
            instance.container.register(:datasource, datasource)

            allow(Facades::Container).to receive(:cache).with(:skip_schema_update).and_return(false)
            allow(Facades::Container).to receive(:cache).with(:schema_path).and_return('/path/to/schema.json')
            allow(Facades::Container).to receive(:cache).with(:is_production).and_return(true)
            allow(Facades::Container).to receive(:cache).with(:append_schema_path).and_return('/path/to/append.json')
            allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive_messages(generate: [], meta: {})
            allow(File).to receive(:exist?).with('/path/to/schema.json').and_return(true)
            allow(File).to receive(:read).with('/path/to/schema.json').and_return({ meta: {}, collections: [] }.to_json)
            allow(File).to receive(:read).with('/path/to/append.json').and_raise(Errno::ENOENT)

            expect { instance.send_schema }.to raise_error(/Can't load additional schema/)
          end

          it 'warns instead of raising if append_schema file cannot be loaded, outside production' do
            instance = described_class.instance
            instance.instance_variable_set(:@has_env_secret, true)
            logger = instance_spy(Services::LoggerService)
            instance.instance_variable_set(:@logger, logger)

            datasource = instance_double(ForestAdminDatasourceToolkit::Datasource)
            instance.container.register(:datasource, datasource)

            allow(Facades::Container).to receive(:cache).with(:skip_schema_update).and_return(false)
            allow(Facades::Container).to receive(:cache).with(:schema_path).and_return('/path/to/schema.json')
            allow(Facades::Container).to receive(:cache).with(:is_production).and_return(false)
            allow(Facades::Container).to receive(:cache).with(:append_schema_path).and_return('/path/to/append.json')
            allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive_messages(generate: [], meta: {})
            allow(File).to receive(:write)
            allow(File).to receive(:read).with('/path/to/append.json').and_raise(Errno::ENOENT)

            expect { instance.send_schema }.not_to raise_error

            expect(logger).to have_received(:log).with('Warn', /Can't load additional schema/)
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

        describe 'chart (DSL method)' do
          it 'provides a fluent DSL for creating charts' do
            instance = described_class.instance
            allow(instance.customizer).to receive(:add_chart)

            result = instance.chart :appointments do
              value 784, 760
            end

            expect(instance.customizer).to have_received(:add_chart).with('appointments')
            expect(result).to eq(instance)
          end

          it 'converts symbol names to strings' do
            instance = described_class.instance
            allow(instance.customizer).to receive(:add_chart)

            instance.chart :my_chart do
              value 123
            end

            expect(instance.customizer).to have_received(:add_chart).with('my_chart')
          end
        end

        describe 'format_schema_json' do
          it 'collapses single-element arrays onto one line' do
            instance = described_class.instance
            schema = {
              collections: [
                {
                  name: 'Book',
                  fields: [
                    { field: 'tags', type: ['String'] },
                    { field: 'scores', type: ['Number'] }
                  ]
                }
              ]
            }

            result = instance.send(:format_schema_json, schema)

            expect(result).to include('"type": ["String"]')
            expect(result).to include('"type": ["Number"]')
            expect(result).not_to match(/"type": \[\s+\n\s+"String"\s+\n\s+\]/)
          end

          it 'keeps multi-element arrays on multiple lines' do
            instance = described_class.instance
            schema = {
              fields: [
                { field: 'status', enums: %w[draft published archived] }
              ]
            }

            result = instance.send(:format_schema_json, schema)

            expect(result).to include('"enums": [')
            expect(result).to include('"draft"')
            expect(result).to include('"published"')
            expect(result).to include('"archived"')
            # Multi-element array should be on multiple lines
            expect(result).to match(/"enums": \[\n/)
          end

          it 'preserves arrays of objects on multiple lines' do
            instance = described_class.instance
            schema = {
              fields: [
                { type: [{ street: 'String', city: 'String' }] }
              ]
            }

            result = instance.send(:format_schema_json, schema)

            # Object arrays should remain on multiple lines
            expect(result).to match(/"type": \[\n/)
            expect(result).to include('"street"')
          end
        end

        describe 'customize_collection' do
          it 'customizes collection and returns self' do
            instance = described_class.instance
            allow(instance.customizer).to receive(:customize_collection)
            handler = proc {}

            result = instance.customize_collection('Book', &handler)

            expect(instance.customizer).to have_received(:customize_collection).with('Book')
            expect(result).to eq(instance)
          end
        end

        describe 'send_schema_to_server' do
          let(:instance) { described_class.instance }
          let(:logger) { instance_double(Services::LoggerService) }
          let(:client) { instance_double(ForestAdminAgent::Http::ForestAdminApiRequester) }
          let(:api_map) { { meta: { schemaFileHash: 'abc123' }, collections: [] } }

          before do
            allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
            allow(ForestAdminAgent::Http::ForestAdminApiRequester).to receive(:new).and_return(client)
            allow(logger).to receive(:log)
          end

          it 'logs success message and posts schema when successful' do
            response = instance_double(Faraday::Response)
            allow(client).to receive(:post).with('/forest/apimaps', api_map.to_json).and_return(response)
            allow(client).to receive(:raise_for_response!).with(response)

            instance.send(:send_schema_to_server, api_map)

            expect(logger).to have_received(:log).with('Info', 'schema was updated, sending new version')
            expect(client).to have_received(:post).with('/forest/apimaps', api_map.to_json)
            expect(client).to have_received(:raise_for_response!).with(response)
          end

          context 'when error occurs with HTTP status' do
            it 'logs error with status 400' do
              error = Faraday::ClientError.new('Bad Request', { status: 400 })
              allow(client).to receive(:post).and_raise(error)

              instance.send(:send_schema_to_server, api_map)

              expect(logger).to have_received(:log).with('Info', 'schema was updated, sending new version')
              expect(logger).to have_received(:log).with('Error', 'Failed to send schema: invalid request (HTTP 400)')
            end

            it 'logs error with status 500' do
              error = Faraday::ServerError.new('Internal Server Error', { status: 500 })
              allow(client).to receive(:post).and_raise(error)

              instance.send(:send_schema_to_server, api_map)

              expect(logger).to have_received(:log).with('Error', 'Failed to send schema: invalid request (HTTP 500)')
            end

            it 'logs error with status 502' do
              error = Faraday::ServerError.new('Bad Gateway', { status: 502 })
              allow(client).to receive(:post).and_raise(error)

              instance.send(:send_schema_to_server, api_map)

              expect(logger).to have_received(:log).with('Error', 'Failed to send schema: invalid request (HTTP 502)')
            end
          end

          context 'when error occurs without HTTP status (unreachable)' do
            it 'logs connection failure message' do
              error = Faraday::ConnectionFailed.new('Failed to open TCP connection')
              allow(client).to receive(:post).and_raise(error)

              instance.send(:send_schema_to_server, api_map)

              expect(logger).to have_received(:log).with('Info', 'schema was updated, sending new version')
              expect(logger).to have_received(:log).with('Error', 'Failed to send schema: cannot reach ForestAdmin server')
            end

            it 'logs timeout error message' do
              error = Faraday::TimeoutError.new('execution expired')
              allow(client).to receive(:post).and_raise(error)

              instance.send(:send_schema_to_server, api_map)

              expect(logger).to have_received(:log).with('Error', 'Failed to send schema: cannot reach ForestAdmin server')
            end
          end
        end

        describe 'do_server_want_schema' do
          let(:instance) { described_class.instance }
          let(:client) { instance_double(ForestAdminAgent::Http::ForestAdminApiRequester) }

          before do
            allow(ForestAdminAgent::Http::ForestAdminApiRequester).to receive(:new).and_return(client)
          end

          it 'returns true when the server asks for the schema' do
            response = instance_double(Faraday::Response, body: { sendSchema: true }.to_json)
            allow(client).to receive(:post).and_return(response)
            allow(client).to receive(:raise_for_response!).with(response)

            expect(instance.send(:do_server_want_schema, 'abc123')).to be true
          end

          it 'returns false when the server already has this schema' do
            response = instance_double(Faraday::Response, body: { sendSchema: false }.to_json)
            allow(client).to receive(:post).and_return(response)
            allow(client).to receive(:raise_for_response!).with(response)

            expect(instance.send(:do_server_want_schema, 'abc123')).to be false
          end

          it 'propagates the error raised by raise_for_response! (e.g. an invalid envSecret)' do
            response = instance_double(Faraday::Response, status: 404, body: '{"errors":[]}')
            allow(client).to receive(:post).and_return(response)
            allow(client).to receive(:raise_for_response!).with(response).and_raise(
              ForestAdminAgent::Http::Exceptions::NotFoundError.new(
                'ForestAdmin server failed to find the project related to the envSecret you configured. ' \
                'Can you check that you copied it properly in the Forest initialization?'
              )
            )

            expect do
              instance.send(:do_server_want_schema, 'abc123')
            end.to raise_error(ForestAdminAgent::Http::Exceptions::NotFoundError, /envSecret/)
          end

          it 'raises InternalServerError when the response body is not valid JSON' do
            response = instance_double(Faraday::Response, status: 200, body: 'not json')
            allow(client).to receive(:post).and_return(response)
            allow(client).to receive(:raise_for_response!).with(response)

            expect do
              instance.send(:do_server_want_schema, 'abc123')
            end.to raise_error(ForestAdminAgent::Http::Exceptions::InternalServerError, /Invalid JSON response/)
          end

          it 'delegates to handle_response_error when the connection itself fails' do
            error = Faraday::ConnectionFailed.new('Failed to open TCP connection')
            allow(client).to receive(:post).and_raise(error)
            allow(client).to receive(:handle_response_error).with(error).and_raise(
              ForestAdminAgent::Http::Exceptions::BadGatewayError.new('Failed to reach ForestAdmin server. Are you online?')
            )

            expect do
              instance.send(:do_server_want_schema, 'abc123')
            end.to raise_error(ForestAdminAgent::Http::Exceptions::BadGatewayError)
          end
        end
      end
    end
  end
end
