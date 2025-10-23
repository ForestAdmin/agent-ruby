require 'spec_helper'
require 'ostruct'

module ForestAdminDatasourceToolkit
  module Utils
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Exceptions

    describe Collection do
      include_context 'with caller'

      describe 'Datasource with Inverse relation missing' do
        let(:datasource) { Datasource.new }
        let(:collection_book) do
          collection = ForestAdminDatasourceToolkit::Collection.new(datasource, 'Book')
          collection.add_fields(
            {
              'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
              'author_id' => ColumnSchema.new(column_type: PrimitiveType::UUID),
              'author' => Relations::ManyToOneSchema.new(
                foreign_key: 'author_id',
                foreign_key_target: 'id',
                foreign_collection: 'Person'
              )
            }
          )

          return collection
        end

        let(:collection_person) do
          collection = ForestAdminDatasourceToolkit::Collection.new(datasource, 'Person')
          collection.add_fields(
            {
              'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true)
            }
          )

          return collection
        end

        before do
          datasource.add_collection(collection_book)
          datasource.add_collection(collection_person)
        end

        it 'get_inverse_relation should not find an inverse when inverse relations is missing' do
          expect(described_class.get_inverse_relation(collection_book, 'author')).to be_nil
        end
      end

      describe 'Datasource with all relations' do
        let(:datasource) { Datasource.new }
        let(:collection_book) do
          collection = ForestAdminDatasourceToolkit::Collection.new(datasource, 'Book')
          collection.add_fields(
            {
              'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
              'reference' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
              'title' => ColumnSchema.new(column_type: PrimitiveType::STRING),
              'myPersons' => Relations::ManyToManySchema.new(
                origin_key: 'bookId',
                origin_key_target: 'id',
                foreign_key: 'personId',
                foreign_key_target: 'id',
                foreign_collection: 'Person',
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

        let(:collection_book_person) do
          collection = ForestAdminDatasourceToolkit::Collection.new(datasource, 'BookPerson')
          collection.add_fields(
            {
              'bookId' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
              'personId' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
              'myBook' => Relations::ManyToOneSchema.new(
                foreign_key: 'bookId',
                foreign_key_target: 'id',
                foreign_collection: 'Book'
              ),
              'myPerson' => Relations::ManyToOneSchema.new(
                foreign_key: 'personId',
                foreign_key_target: 'id',
                foreign_collection: 'Person'
              )
            }
          )

          return collection
        end

        let(:collection_person) do
          collection = ForestAdminDatasourceToolkit::Collection.new(datasource, 'Person')
          collection.add_fields(
            {
              'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true,
                                       filter_operators: [ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::IN, ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::EQUAL]),
              'name' => ColumnSchema.new(column_type: PrimitiveType::STRING),
              'myBooks' => Relations::ManyToManySchema.new(
                origin_key: 'personId',
                origin_key_target: 'id',
                foreign_key: 'bookId',
                foreign_key_target: 'id',
                foreign_collection: 'Book',
                through_collection: 'BookPerson'
              ),
              'myBookPerson' => Relations::OneToOneSchema.new(
                origin_key: 'personId',
                origin_key_target: 'id',
                foreign_collection: 'BookPerson'
              )
            }
          )

          return collection
        end

        let(:collection_comment) do
          collection = ForestAdminDatasourceToolkit::Collection.new(datasource, 'Comment')
          collection.add_fields(
            {
              'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true,
                                       filter_operators: [ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::IN, ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::EQUAL]),
              'name' => ColumnSchema.new(column_type: PrimitiveType::STRING),
              'commentable_id' => ColumnSchema.new(column_type: 'Number'),
              'commentable_type' => ColumnSchema.new(column_type: 'String'),
              'commentable' => Relations::PolymorphicManyToOneSchema.new(
                foreign_key_type_field: 'commentable_type',
                foreign_collections: %w[Book],
                foreign_key_targets: { 'Book' => 'id' },
                foreign_key: 'commentable_id'
              )
            }
          )

          return collection
        end

        before do
          datasource.add_collection(collection_book)
          datasource.add_collection(collection_book_person)
          datasource.add_collection(collection_person)
          datasource.add_collection(collection_comment)
        end

        it 'get_inverse_relation should inverse a polymorphic one to many relation' do
          expect(described_class.get_inverse_relation(collection_book, 'comments')).to eq('commentable')
        end

        it 'get_inverse_relation should inverse a one to many relation in both directions' do
          expect(described_class.get_inverse_relation(collection_book, 'myBookPersons')).to eq('myBook')
        end

        it 'get_inverse_relation should inverse a many to many relation in both directions' do
          expect(described_class.get_inverse_relation(collection_book, 'myPersons')).to eq('myBooks')
          expect(described_class.get_inverse_relation(collection_person, 'myBooks')).to eq('myPersons')
        end

        it 'get_inverse_relation should inverse a one to one relation in both directions' do
          expect(described_class.get_inverse_relation(collection_person, 'myBookPerson')).to eq('myPerson')
          expect(described_class.get_inverse_relation(collection_book_person, 'myPerson')).to eq('myBookPerson')
        end

        it 'is_many_to_one_inverse? should return false when the relation does not exist' do
          many_to_many_relation = Relations::ManyToManySchema.new(
            origin_key: 'fooId',
            origin_key_target: 'id',
            foreign_key: 'bookId',
            foreign_key_target: 'id',
            foreign_collection: 'Book',
            through_collection: 'BookFoo'
          )

          expect(described_class.many_to_one_inverse?(collection_book.schema[:fields]['myPersons'],
                                                      many_to_many_relation)).to be false
        end

        it 'is_many_to_one_inverse? should return true on a bidirectional relation' do
          expect(described_class.many_to_many_inverse?(collection_book.schema[:fields]['myPersons'],
                                                       collection_person.schema[:fields]['myBooks'])).to be true
        end

        it 'is_many_to_one_inverse? should return false' do
          expect(described_class.many_to_one_inverse?(collection_book_person.schema[:fields]['myBook'],
                                                      collection_person.schema[:fields]['myBookPerson'])).to be false
        end

        it 'is_many_to_one_inverse? should return true' do
          expect(described_class.many_to_one_inverse?(collection_book_person.schema[:fields]['myBook'],
                                                      collection_book.schema[:fields]['myBookPersons'])).to be true
        end

        it 'is_other_inverse? should return false' do
          expect(described_class.other_inverse?(collection_person.schema[:fields]['myBookPerson'],
                                                collection_book_person.schema[:fields]['myBook'])).to be false
        end

        it 'is_other_inverse? should return true' do
          expect(described_class.other_inverse?(collection_person.schema[:fields]['myBookPerson'],
                                                collection_book_person.schema[:fields]['myPerson'])).to be true
        end

        it 'get_field_schema should throw with unknown column' do
          expect do
            described_class.get_field_schema(collection_person,
                                             'foo')
          end.to raise_error(ForestException, 'Column not found Person.foo')
        end

        it 'get_field_schema should work with simple column' do
          expect(described_class.get_field_schema(collection_person, 'name'))
            .to have_attributes(class: ColumnSchema, column_type: PrimitiveType::STRING)
        end

        it 'get_field_schema should throw with unknown relation:column' do
          expect do
            described_class.get_field_schema(collection_person,
                                             'unknown:foo')
          end.to raise_error(ForestException, 'Relation not found Person.unknown')
        end

        it 'get_field_schema should throw with invalid relation type' do
          expect do
            described_class.get_field_schema(collection_book,
                                             'myBookPersons:bookId')
          end.to raise_error(ForestException, 'Unexpected field type OneToMany: Book.myBookPersons')
        end

        it 'get_field_schema should work with relation column' do
          expect(described_class.get_field_schema(collection_book_person, 'myPerson:name'))
            .to have_attributes(class: ColumnSchema, column_type: PrimitiveType::STRING)
        end

        it 'get_through_target should throw with invalid relation type' do
          expect do
            described_class.get_through_target(collection_book,
                                               'myBookPersons')
          end.to raise_error(ForestException, 'Relation must be many to many')
        end

        it 'get_through_target should work' do
          expect(described_class.get_through_target(collection_book, 'myPersons')).to eq('myPerson')
        end

        it 'get_through_origin should throw with invalid relation type' do
          expect do
            described_class.get_through_origin(collection_book,
                                               'myBookPersons')
          end.to raise_error(ForestException, 'Relation must be many to many')
        end

        it 'get_through_origin should work' do
          expect(described_class.get_through_origin(collection_book, 'myPersons')).to eq('myBook')
        end

        it 'get_value should work' do
          allow(collection_person).to receive(:list).and_return([{ 'id' => 1, 'name' => 'foo' }])

          expect(described_class.get_value(collection_person, caller, [1], 'name')).to eq('foo')
        end

        it 'get_value should work with composite id' do
          allow(collection_book).to receive(:list).and_return([{ 'id' => 1, 'reference' => 'ref', 'title' => 'foo' }])

          expect(described_class.get_value(collection_book, caller, [1, 'ref'], 'reference')).to eq('ref')
        end

        it 'get_value should work with custom primary key field using hash id' do
          allow(collection_person).to receive(:list).and_return([{ 'id' => 1, 'name' => 'John Doe' }])

          expect(described_class.get_value(collection_person, caller, { 'id' => 1 }, 'name')).to eq('John Doe')
        end

        it 'list_relation should work with one to many relation' do
          allow(collection_book_person).to receive(:list).and_return([{ 'bookId' => 1, 'personId' => 1 }])

          expect(described_class.list_relation(collection_book, [1], 'myBookPersons', caller, ForestAdminDatasourceToolkit::Components::Query::Filter.new,
                                               ForestAdminDatasourceToolkit::Components::Query::Projection.new)).to eq([{
                                                                                                                         'bookId' => 1, 'personId' => 1
                                                                                                                       }])
        end

        it 'list_relation should work with many to many relation' do
          book_person_class = Struct.new(:bookId, :personId, :myPerson, :myBook)
          stub_const('BookPerson', book_person_class)
          allow(collection_person).to receive(:list).and_return([{ 'id' => 1, 'name' => 'foo' }])
          allow(collection_book_person).to receive(:list).and_return(
            [
              BookPerson.new(1, 1, 1, 1)
            ]
          )

          expect(described_class.list_relation(collection_book, [1], 'myPersons', caller, ForestAdminDatasourceToolkit::Components::Query::Filter.new,
                                               ForestAdminDatasourceToolkit::Components::Query::Projection.new)).to eq([1])
        end

        it 'aggregate_relation should work with one to many relation' do
          allow(collection_book_person).to receive(:aggregate).and_return(1)

          expect(described_class.aggregate_relation(collection_book, [1], 'myBookPersons', caller, ForestAdminDatasourceToolkit::Components::Query::Filter.new,
                                                    ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(operation: 'Count'))).to eq(1)
        end

        it 'aggregate_relation should work with many to many relation' do
          allow(collection_person).to receive(:aggregate).and_return(1)
          allow(collection_book_person).to receive(:aggregate).and_return(1)

          expect(described_class.aggregate_relation(collection_book, [1], 'myPersons', caller, ForestAdminDatasourceToolkit::Components::Query::Filter.new,
                                                    ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(operation: 'Count'))).to eq(1)
        end
      end
    end
  end
end
