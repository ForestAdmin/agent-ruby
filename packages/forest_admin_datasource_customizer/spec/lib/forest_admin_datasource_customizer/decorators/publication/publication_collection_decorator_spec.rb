require 'spec_helper'
require 'shared/caller'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Publication
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Exceptions

      describe PublicationCollectionDecorator do
        include_context 'with caller'
        let(:datasource) { ForestAdminDatasourceToolkit::Datasource.new }

        before do
          @collection_book = instance_double(
            ForestAdminDatasourceToolkit::Collection,
            name: 'book',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, is_read_only: true),
                'my_persons' => Relations::ManyToManySchema.new(
                  origin_key: 'book_id',
                  origin_key_target: 'id',
                  foreign_key: 'person_id',
                  foreign_key_target: 'id',
                  foreign_collection: 'person',
                  through_collection: 'book_person'
                ),
                'my_book_persons' => Relations::OneToManySchema.new(
                  foreign_collection: 'book_person',
                  origin_key: 'book_id',
                  origin_key_target: 'id'
                )
              }
            }
          )

          @collection_book_person = instance_double(
            ForestAdminDatasourceToolkit::Collection,
            name: 'book_person',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'book_id' => ColumnSchema.new(column_type: 'Number'),
                'person_id' => ColumnSchema.new(column_type: 'Number'),
                'my_book' => Relations::ManyToOneSchema.new(
                  foreign_collection: 'book',
                  foreign_key: 'book_id',
                  foreign_key_target: 'id'
                ),
                'my_person' => Relations::ManyToOneSchema.new(
                  foreign_collection: 'person',
                  foreign_key: 'person_id',
                  foreign_key_target: 'id'
                ),
                'date' => ColumnSchema.new(column_type: 'Date')
              }
            }
          )

          @collection_person = instance_double(
            ForestAdminDatasourceToolkit::Collection,
            name: 'person',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'my_book_person' => Relations::OneToOneSchema.new(
                  foreign_collection: 'book_person',
                  origin_key: 'person_id',
                  origin_key_target: 'id'
                )
              }
            }
          )

          datasource.add_collection(@collection_book)
          datasource.add_collection(@collection_book_person)
          datasource.add_collection(@collection_person)

          datasource_decorator = PublicationDatasourceDecorator.new(datasource)

          @decorated_book = datasource_decorator.get_collection('book')
          @decorated_book_person = datasource_decorator.get_collection('book_person')
          @decorated_person = datasource_decorator.get_collection('person')
        end

        it 'throws when hiding a field which does not exists' do
          expect { @decorated_person.change_field_visibility('unknown', false) }.to raise_error(ForestException, "🌳🌳🌳 No such field 'unknown'")
        end

        it 'throws when hiding the primary key' do
          expect { @decorated_person.change_field_visibility('id', false) }.to raise_error(ForestException, '🌳🌳🌳 Cannot hide primary key')
        end

        it 'the schema should be the same when doing nothing' do
          expect(@decorated_person.schema).to eq(@collection_person.schema)
          expect(@decorated_book_person.schema).to eq(@collection_book_person.schema)
          expect(@decorated_book.schema).to eq(@collection_book.schema)
        end

        it 'the schema should be the same when hiding and showing fields again' do
          @decorated_person.change_field_visibility('my_book_person', false)
          @decorated_person.change_field_visibility('my_book_person', true)

          expect(@decorated_person.schema).to eq(@collection_person.schema)
        end

        context 'when hiding normal fields' do
          before do
            @decorated_book_person.change_field_visibility('date', false)
          end

          it 'the field should be removed from the schema of the collection' do
            expect(@decorated_book_person.schema[:fields]).not_to have_key('date')
          end

          it 'other fields should not be affected' do
            expect(@decorated_book_person.schema[:fields]).to have_key('book_id')
            expect(@decorated_book_person.schema[:fields]).to have_key('person_id')
            expect(@decorated_book_person.schema[:fields]).to have_key('my_book')
            expect(@decorated_book_person.schema[:fields]).to have_key('my_person')
          end

          it 'other collections should not be affected' do
            expect(@decorated_person.schema).to eq(@collection_person.schema)
            expect(@decorated_book.schema).to eq(@collection_book.schema)
          end

          it 'create should proxies return value (removing extra columns)' do
            created = { 'id' => 1, 'book_id' => 2, 'person_id' => 3, 'date' => '1985-10-26' }
            allow(@collection_book_person).to receive(:create).and_return([created])

            result = @decorated_book_person.create(caller, [{ 'something' => true }])
            expect(result).to eq([{ 'id' => 1, 'book_id' => 2, 'person_id' => 3 }])
          end
        end

        context 'when hiding foreign keys' do
          before do
            @decorated_book_person.change_field_visibility('book_id', false)
          end

          it 'the fk should be hidden' do
            expect(@decorated_book_person.schema[:fields]).not_to have_key('book_id')
          end

          it 'all linked relations should be removed as well' do
            expect(@decorated_book_person.schema[:fields]).not_to have_key('my_book')
            expect(@decorated_book.schema[:fields]).not_to have_key('my_persons')
            expect(@decorated_book.schema[:fields]).not_to have_key('my_book_persons')
          end

          it 'relations which do not depend on this fk should be left alone' do
            expect(@decorated_book_person.schema[:fields]).to have_key('my_person')
            expect(@decorated_person.schema[:fields]).to have_key('my_book_person')
          end
        end
      end
    end
  end
end
