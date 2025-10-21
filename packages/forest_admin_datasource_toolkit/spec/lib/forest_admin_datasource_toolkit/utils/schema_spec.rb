require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Utils
    include ForestAdminDatasourceToolkit::Schema
    describe Schema do
      let(:collection) do
        collection = ForestAdminDatasourceToolkit::Collection.new(Datasource.new, '__collection__')
        collection.add_fields(
          {
            'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
            'composite_id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
            'author_id' => ColumnSchema.new(column_type: 'Number'),
            'author' => Relations::ManyToOneSchema.new(
              foreign_key: 'author_id',
              foreign_key_target: 'id',
              foreign_collection: 'Person'
            ),
            'myBooks' => Relations::ManyToManySchema.new(
              origin_key: 'personId',
              origin_key_target: 'id',
              foreign_key: 'bookId',
              foreign_key_target: 'id',
              foreign_collection: 'Book',
              through_collection: 'BookPerson'
            ),
            'myBookPersons' => Relations::OneToManySchema.new(
              origin_key: 'bookId',
              origin_key_target: 'id',
              foreign_collection: 'BookPerson'
            ),
            'comments' => Relations::PolymorphicOneToManySchema.new(
              origin_key: 'commentable_id',
              foreign_collection: 'Comment',
              origin_key_target: 'id',
              origin_type_field: 'commentable_type',
              origin_type_value: 'Book'
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

      describe 'get_to_many_relation' do
        it 'raise an error when relation do not exist' do
          expect { described_class.get_to_many_relation(collection, 'foo') }.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException, 'Relation foo not found'
          )
        end

        it 'raise an error when the relation is not a to_many relation' do
          expect { described_class.get_to_many_relation(collection, 'author') }.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            'Relation author has invalid type should be one of OneToMany or ManyToMany.'
          )
        end

        it 'return the relation' do
          expect(described_class.get_to_many_relation(collection, 'comments')).to eq(
            collection.schema[:fields]['comments']
          )
          expect(described_class.get_to_many_relation(collection, 'myBookPersons')).to eq(
            collection.schema[:fields]['myBookPersons']
          )
        end
      end
    end
  end
end
