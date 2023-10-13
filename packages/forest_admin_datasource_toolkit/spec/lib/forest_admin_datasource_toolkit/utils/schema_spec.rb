require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Utils
    include ForestAdminDatasourceToolkit::Schema
    describe Schema do
      let(:collection) do
        collection = Collection.new(Datasource.new, '__collection__')
        collection.add_fields(
          {
            'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
            'composite_id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
            'author_id' => ColumnSchema.new(column_type: 'Number'),
            'author' => Relations::ManyToOneSchema.new(
              foreign_key: 'author_id',
              foreign_key_target: 'id',
              foreign_collection: 'Person'
            )
          }
        )

        return collection
      end

      describe 'foreign_key?' do
        it 'return true when field is a foreign_key' do
          expect(described_class.foreign_key?(collection, 'author_id')).to be true
        end

        it 'return false when field is not a foreign_key' do
          expect(described_class.foreign_key?(collection, 'id')).to be false
        end
      end

      describe 'primary_key?' do
        it 'return true when field is a primary_key' do
          expect(described_class.primary_key?(collection, 'id')).to be true
        end

        it 'return false when field is not a primary_key' do
          expect(described_class.primary_key?(collection, 'author_id')).to be false
        end
      end

      describe 'primary_keys' do
        it 'return all primary_keys of the collection' do
          expect(described_class.primary_keys(collection)).to eq(%w[id composite_id])
        end
      end
    end
  end
end
