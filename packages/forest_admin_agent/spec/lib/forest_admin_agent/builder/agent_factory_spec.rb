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
            expect(described_class.instance.container.resolve(:cache)).to be_instance_of Lightly
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
            AgentFactory.instance.add_datasource(datasource)

            expect(AgentFactory.instance.customizer.collections.size).to eq(1)
            expect(AgentFactory.instance.customizer.collection('Book')).to eq(collection_book)
            expect(AgentFactory.instance.customizer.collection('Book').datasource).to eq(datasource)
          end
        end

        describe 'build' do
          it 'add customizer to the container' do
            allow(AgentFactory.instance).to receive(:send_schema)
            AgentFactory.instance.build

            expect(AgentFactory.instance.container.resolve(:datasource)).to eq(AgentFactory.instance.customizer)
          end
        end

        describe 'send_schema' do
          it 'do nothing if env_secret is nil' do
            AgentFactory.instance.instance_variable_set('@has_env_secret', false)
            allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive(:get_serialized_schema)
            AgentFactory.instance.build

            expect(ForestAdminAgent::Utils::Schema::SchemaEmitter).not_to have_received(:get_serialized_schema)
          end

          it 'send schema when schema hash is different' do
            allow(AgentFactory.instance).to receive(:has_env_secret).and_return(false)
            allow(ForestAdminAgent::Utils::Schema::SchemaEmitter).to receive(:get_serialized_schema)
              .and_return(
                {
                  meta: {
                    schemaFileHash: ''
                  }
                }
              )

            expect_any_instance_of(ForestAdminAgent::Http::ForestAdminApiRequester).to receive(:post)
            AgentFactory.instance.build
          end
        end
      end
    end
  end
end

