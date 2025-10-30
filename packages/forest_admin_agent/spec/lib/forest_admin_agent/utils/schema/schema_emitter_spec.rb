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

          @schema_path = Facades::Container.cache(:schema_path)
          generated = described_class.generate(@datasource)
          meta = described_class.meta

          @schema = {
            meta: meta,
            collections: generated
          }

          File.write(@schema_path, JSON.pretty_generate(@schema))
        end

        context 'when env is not production' do
          before do
            config = ForestAdminAgent::Builder::AgentFactory.instance.container.resolve(:config)
            config[:is_production] = false
          end

          it 'serialize schema' do
            schema_serialized = described_class.serialize(@schema)

            expect(schema_serialized).to include(:data, :included, :meta)
            expect(schema_serialized[:data][0].keys).to eq(%i[id type attributes relationships])
            expect(schema_serialized[:data][0][:attributes].keys).to eq(
              %i[fields icon integration isReadOnly isSearchable isVirtual name onlyForRelationships paginationType]
            )
            expect(schema_serialized[:data][0][:relationships].keys).to eq(%i[actions segments])
            expect(schema_serialized[:data][0][:relationships][:actions].keys).to eq(%i[data])
            expect(schema_serialized[:data][0][:relationships][:segments].keys).to eq(%i[data])
          end
        end

        describe 'serialize' do
          it 'adds schemaFileHash to meta' do
            expected_hash = Digest::SHA1.hexdigest(@schema[:collections].to_json)
            serialized = described_class.serialize(@schema)

            expect(serialized[:meta][:schemaFileHash]).to eq(expected_hash)
          end
        end

        describe 'meta' do
          it 'returns correct liana info and ruby engine version' do
            meta = described_class.meta

            expect(meta[:liana]).to eq('agent-ruby')
            expect(meta[:liana_version]).to eq(described_class::LIANA_VERSION)
            expect(meta[:stack][:engine]).to eq('ruby')
            expect(meta[:stack][:engine_version]).to eq(RUBY_VERSION)
          end
        end

        describe 'generate' do
          it 'returns collections sorted by name' do
            ds = Datasource.new
            col_b = Collection.new(ds, 'B')
            col_a = Collection.new(ds, 'A')
            ds.add_collection(col_b)
            ds.add_collection(col_a)

            generated = described_class.generate(ds)

            expect(generated.map { |c| c[:name] }).to eq(%w[A B])
          end

          it 'returns an empty array when datasource has no collections' do
            ds = Datasource.new
            generated = described_class.generate(ds)
            expect(generated).to eq([])
          end
        end
      end
    end
  end
end
