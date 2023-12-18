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

            expect(described_class.instance.customizer.collections.size).to eq(1)
            expect(described_class.instance.customizer.get_collection('Book').name).to eq('Book')
          end
        end

        describe 'build' do
          it 'add datasource to the container' do
            allow(described_class.instance).to receive(:send_schema)
            described_class.instance.build

            expect(described_class.instance.container.resolve(:datasource))
              .to eq(described_class.instance.customizer.datasource)
          end
        end

        describe 'send_schema' do
          it 'do nothing if env_secret is nil' do
            described_class.instance.instance_variable_set(:@has_env_secret, false)
            allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive(:get_serialized_schema)
            described_class.instance.build

            expect(ForestAdminAgent::Utils::Schema::SchemaEmitter).not_to have_received(:get_serialized_schema)
          end

          # it 'send schema when schema hash is different' do
          #   allow(described_class.instance).to receive(:has_env_secret).and_return(false)
          #   allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive(:get_serialized_schema)
          #   allow(ForestAdminAgent::Http::ForestAdminApiRequester).to receive(:post)
          #     .and_return(
          #       {
          #         meta: {
          #           schemaFileHash: ''
          #         }
          #       }
          #     )
          #
          #   described_class.instance.build
          #   expect(ForestAdminAgent::Http::ForestAdminApiRequester).to receive(:post)
          # end
        end
      end
    end
  end
end
