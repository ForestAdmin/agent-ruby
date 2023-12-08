require 'spec_helper'
require 'digest/sha1'
require 'json'

module ForestAdminAgent
  module Utils
    module Schema
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Schema

      describe SchemaEmitter do
        before do
          @datasource = Datasource.new
          collection_book = Collection.new(@datasource, 'Book')
          collection_book.add_fields(
            {
              'id' => ColumnSchema.new(column_type: '', is_primary_key: true),
              'author_id' => ColumnSchema.new(column_type: 'Number'),
              'author' => Relations::ManyToOneSchema.new(
                foreign_key: 'author_id',
                foreign_key_target: 'id',
                foreign_collection: 'Person'
              )
            }
          )
          collection_person = Collection.new(@datasource, 'Person')
          collection_person.add_fields(
            {
              'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
              'book' => Relations::OneToOneSchema.new(
                origin_key: 'author_id',
                origin_key_target: 'id',
                foreign_collection: 'Book'
              )
            }
          )

          @datasource.add_collection(collection_book)
          @datasource.add_collection(collection_person)
        end

        context 'when env is not production' do
          before do
            cache = ForestAdminAgent::Builder::AgentFactory.instance.container.resolve(:cache)
            config = cache.get('config')
            cache.clear
            config[:is_production] = false
            cache.get_or_set 'config' do
              config
            end
          end

          it 'generate serialized schema' do
            schema = described_class.get_serialized_schema(@datasource)

            expect(schema).to include(:data, :included, :meta)
            expect(schema[:data][0].keys).to eq(%i[id type attributes relationships])
            expect(schema[:data][0][:attributes].keys).to eq(
              %i[fields icon integration isReadOnly isSearchable isVirtual name onlyForRelationships paginationType]
            )
            expect(schema[:data][0][:relationships].keys).to eq(%i[actions segments])
            expect(schema[:data][0][:relationships][:actions].keys).to eq(%i[data])
            expect(schema[:data][0][:relationships][:segments].keys).to eq(%i[data])
          end

          it 'generate the schema json' do
            schema_path = Facades::Container.cache(:schema_path)
            FileUtils.rm_f schema_path
            described_class.get_serialized_schema(@datasource)

            expect(File.exist?(schema_path)).to be true
          end
        end

        context 'when env is production' do
          before do
            cache = ForestAdminAgent::Builder::AgentFactory.instance.container.resolve(:cache)
            config = cache.get('config')
            cache.clear
            config[:is_production] = true
            cache.get_or_set 'config' do
              config
            end
          end

          it 'generate empty serialized schema when json does not exist' do
            schema_path = Facades::Container.cache(:schema_path)
            FileUtils.rm_f schema_path
            schema = described_class.get_serialized_schema(@datasource)

            expect(schema).to eq(
              {
                data: [],
                included: nil,
                meta: {
                  liana: described_class::LIANA_NAME,
                  liana_version: described_class::LIANA_VERSION,
                  stack: {
                    engine: 'ruby',
                    engine_version: RUBY_VERSION
                  },
                  schemaFileHash: Digest::SHA1.hexdigest('')
                }
              }
            )
          end

          it 'generate serialized schema with the existing json' do
            schema_path = Facades::Container.cache(:schema_path)
            FileUtils.rm_f schema_path
            json_schema = {
              meta: {
                liana: 'agent-ruby',
                liana_version: 'beta',
                stack: { engine: 'ruby', engine_version: '3.2.0' },
                schemaFileHash: 'c3af464045ea4b3a2ddefd986a19b746680e1177'
              },
              collections: []
            }
            File.write(schema_path, JSON.pretty_generate(json_schema))
            schema = described_class.get_serialized_schema(@datasource)

            expect(schema).to eq(
              {
                data: [],
                included: nil,
                meta: json_schema[:meta]
              }
            )
          end
        end
      end
    end
  end
end
