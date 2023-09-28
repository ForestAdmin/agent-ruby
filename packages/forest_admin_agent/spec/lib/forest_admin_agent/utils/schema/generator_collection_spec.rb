require 'spec_helper'

module ForestAdminAgent
  module Utils
    module Schema
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Schema
      describe GeneratorCollection do
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
              'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, is_read_only: true),
              'my_self' => Relations::OneToOneSchema.new(
                origin_key: 'id',
                origin_key_target: 'id',
                foreign_collection: 'Person'
              )
            }
          )

          @datasource.add_collection(collection_book)
          @datasource.add_collection(collection_person)
        end

        it 'generate schema with readonly false and skipped foreign keys' do
          schema = described_class.build_schema(@datasource.collection('Book'))

          expect(schema[:isReadOnly]).to be false
          expect(schema[:fields].size).to eq 2
          expect(schema[:fields][0][:field]).to eq 'author'
          expect(schema[:fields][1][:field]).to eq 'id'
        end

        it 'generate schema with readonly true' do
          schema = described_class.build_schema(@datasource.collection('Person'))

          expect(schema[:isReadOnly]).to be true
        end

        it 'have an id, regardless of the fact that it is also a fk on Person collection' do
          schema = described_class.build_schema(@datasource.collection('Person'))

          expect(schema[:fields][0][:field]).to eq 'id'
          expect(schema[:fields][0][:isPrimaryKey]).to be true
        end

        it 'have a one-to-one relationship' do
          schema = described_class.build_schema(@datasource.collection('Person'))

          expect(schema[:fields][1]).to include(
            field: 'my_self',
            isPrimaryKey: false, # Otherwise the UI will try to use it as a column
            isReadOnly: true, # because the foreignKey that is being used is readonly
            reference: 'Person.id',
            relationship: 'HasOne'
          )
        end
      end
    end
  end
end
