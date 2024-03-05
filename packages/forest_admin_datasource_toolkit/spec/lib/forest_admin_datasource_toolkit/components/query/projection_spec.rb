require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Query
      include ForestAdminDatasourceToolkit::Schema
      describe Projection do
        let(:collection) do
          collection = Collection.new(Datasource.new, '__collection__')
          collection.add_fields(
            {
              'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
              'name' => ColumnSchema.new(column_type: PrimitiveType::STRING)
            }
          )

          return collection
        end

        describe 'with_pks' do
          it 'automatically add pks to the provided projection when the pk is a single field' do
            projection = described_class.new(['name']).with_pks(collection)
            expect(projection).to eq(described_class.new(%w[name id]))
          end

          it 'do nothing when the pks are already provided and the pk is a single field' do
            projection = described_class.new(%w[name id]).with_pks(collection)
            expect(projection).to eq(described_class.new(%w[name id]))
          end

          it 'automatically add pks to the provided projection when the pk is a composite' do
            collection = Collection.new(Datasource.new, '__collection__')
            collection.add_fields(
              {
                'key1' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
                'key2' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
                'name' => ColumnSchema.new(column_type: PrimitiveType::STRING)
              }
            )
            projection = described_class.new(['name']).with_pks(collection)
            expect(projection).to eq(described_class.new(%w[name key1 key2]))
          end
        end

        describe 'nest' do
          it 'do nothing with null' do
            projection = described_class.new(%w[id name author:name other:id])
            expect(projection.nest).to eq projection
          end

          it 'work with a prefix' do
            projection = described_class.new(%w[id name author:name other:id])
            expect(projection.nest(prefix: 'prefix')).to eq(
              described_class.new(%w[prefix:id prefix:name prefix:author:name prefix:other:id])
            )
          end
        end

        describe 'columns' do
          it 'return only fields of a collection' do
            projection = described_class.new(%w[id name category:label])

            expect(projection.columns).to eq(%w[id name])
          end
        end

        describe 'relations' do
          it 'return only the relations of a collection' do
            projection = described_class.new(%w[id name category:label])

            expect(projection.relations).to eq({ 'category' => ['label'] })
          end
        end

        describe 'apply' do
          it 're_projects a list of records' do
            projection = described_class.new(%w[id name author:name other:id])

            expect(
              projection.apply([
                                 {
                                   id: 1,
                                   name: 'romain',
                                   age: 12,
                                   author: { name: 'ana', lastname: 'something' },
                                   other: nil
                                 }
                               ])
            ).to eq(
              [
                {
                  'id' => 1,
                  'name' => 'romain',
                  'author' => { 'name' => 'ana' },
                  'other' => nil
                }
              ]
            )
          end
        end
      end
    end
  end
end
