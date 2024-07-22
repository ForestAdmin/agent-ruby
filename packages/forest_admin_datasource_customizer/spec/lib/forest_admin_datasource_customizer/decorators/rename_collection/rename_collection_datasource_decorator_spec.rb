require 'spec_helper'
require 'shared/caller'

module ForestAdminDatasourceCustomizer
  module Decorators
    module RenameCollection
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Decorators
      include ForestAdminDatasourceToolkit::Schema

      describe RenameCollectionDatasourceDecorator do
        include_context 'with caller'
        subject(:rename_collection_decorator) { described_class }

        it 'return the real name when it is not renamed' do
          datasource = datasource_with_collections_build(
            [collection_build(name: 'foo', schema: { fields: { 'id' => numeric_primary_key_build } })]
          )
          decorated_datasource = described_class.new(datasource)
          collection = decorated_datasource.get_collection('foo')

          expect(collection.name).to eq('foo')
        end

        it 'return the new name when it is renamed' do
          datasource = datasource_with_collections_build(
            [collection_build(name: 'foo', schema: { fields: { 'id' => numeric_primary_key_build } })]
          )
          decorated_datasource = described_class.new(datasource)
          decorated_datasource.rename_collection('foo', 'new_name')

          expect(decorated_datasource.get_collection('new_name')).not_to be_nil
          expect do
            decorated_datasource.get_collection('foo')
          end.to raise_error(Exceptions::ForestException)
        end

        context 'with ManyToMany relation' do
          before do
            @collection_library = collection_build(
              name: 'library',
              schema: {
                fields: {
                  'id' => numeric_primary_key_build,
                  'many_to_many_relation' => many_to_many_build(
                    foreign_collection: 'book',
                    origin_key: 'library_id',
                    through_collection: 'library_book',
                    foreign_key: 'book_id'
                  )
                }
              }
            )

            @collection_library_book = collection_build(
              name: 'library_book',
              schema: {
                fields: {
                  'book_id' => numeric_primary_key_build,
                  'library_id' => numeric_primary_key_build,
                  'my_book' => many_to_one_build(foreign_collection: 'book', foreign_key: 'book_id'),
                  'my_library' => many_to_one_build(foreign_collection: 'library', foreign_key: 'library_id')
                }
              }
            )

            @collection_book = collection_build(
              name: 'book',
              schema: {
                fields: {
                  'id' => numeric_primary_key_build,
                  'many_to_many_relation' => many_to_many_build(
                    foreign_collection: 'library',
                    origin_key: 'book_id',
                    through_collection: 'library_book',
                    foreign_key: 'library_id'
                  )
                }
              }
            )

            @datasource = described_class.new(
              datasource_with_collections_build(
                [
                  @collection_book,
                  @collection_library_book,
                  @collection_library
                ]
              )
            )
          end

          describe 'rename_collection' do
            it 'raise an error if the given new name is already used' do
              expect do
                @datasource.rename_collection('library_book', 'book')
              end.to raise_error(
                Exceptions::ForestException,
                "🌳🌳🌳 The given new collection name 'book' is already defined"
              )
            end

            it 'raise an error if renaming twice' do
              @datasource.rename_collection('book', 'book2')
              expect do
                @datasource.rename_collection('book2', 'book3')
              end.to raise_error(
                Exceptions::ForestException,
                '🌳🌳🌳 Cannot rename a collection twice: book->book2->book3'
              )
            end

            it 'raise an error if the given old name does not exist' do
              expect do
                @datasource.rename_collection('doesNotExist', 'book')
              end.to raise_error(
                Exceptions::ForestException,
                '🌳🌳🌳 Collection doesNotExist not found.'
              )
            end

            it 'change the foreign collection when it is a many to many' do
              @datasource.rename_collection('library_book', 'renamed_library_book')
              @datasource.rename_collection('book', 'renamed_book')
              collection = @datasource.get_collection('library')

              expect(collection.schema[:fields]['many_to_many_relation']).to have_attributes(
                foreign_collection: 'renamed_book',
                origin_key: 'library_id',
                through_collection: 'renamed_library_book',
                foreign_key: 'book_id'
              )
            end
          end

          describe 'rename_collections' do
            it 'work with undefined' do
              @datasource.rename_collections

              expect(@datasource.collections.keys).to include('library_book')
            end

            it 'work when using a hash' do
              @datasource.rename_collections({ 'library_book' => 'renamed_library_book' })
              collection_name = @datasource.collections.map { |_key, collection| collection.name }

              expect(collection_name).to include('renamed_library_book')
            end
          end
        end

        context 'with OneToOne relation' do
          before do
            @collection_book = collection_build(
              name: 'book',
              schema: {
                fields: {
                  'id' => numeric_primary_key_build,
                  'owner' => one_to_one_build(foreign_collection: 'owner', origin_key: 'book_id')
                }
              }
            )

            @collection_owner = collection_build(
              name: 'owner',
              schema: {
                fields: {
                  'id' => numeric_primary_key_build,
                  'book_id' => column_build,
                  'owner' => many_to_one_build(foreign_collection: 'owner', foreign_key: 'book_id')
                }
              }
            )

            @datasource = described_class.new(datasource_with_collections_build([@collection_book, @collection_owner]))
          end

          describe 'rename_collection' do
            it 'change the foreign collection when it is a one to one' do
              @datasource.rename_collection('owner', 'renamed_owner')
              collection = @datasource.get_collection('book')

              expect(collection.schema[:fields]['owner']).to have_attributes(
                foreign_collection: 'renamed_owner',
                origin_key: 'book_id',
                origin_key_target: 'id',
                type: 'OneToOne'
              )
            end
          end
        end

        context 'with ManyToOne and OneToMany relation' do
          before do
            @collection_book = collection_build(
              name: 'book',
              schema: {
                fields: {
                  'id' => numeric_primary_key_build,
                  'person_id' => column_build,
                  'my_person' => many_to_one_build(foreign_collection: 'person', foreign_key: 'person_id')
                }
              }
            )

            @collection_person = collection_build(
              name: 'person',
              schema: {
                fields: {
                  'id' => numeric_primary_key_build,
                  'name' => column_build,
                  'my_books' => one_to_many_build(foreign_collection: 'book', origin_key: 'id')
                }
              }
            )

            @datasource = described_class.new(datasource_with_collections_build([@collection_book, @collection_person]))
          end

          describe 'rename_collection' do
            it 'change the foreign collection when it is a many to one' do
              @datasource.rename_collection('person', 'renamed_person')
              collection = @datasource.get_collection('book')

              expect(collection.schema[:fields]['my_person']).to have_attributes(
                foreign_collection: 'renamed_person',
                foreign_key: 'person_id',
                foreign_key_target: 'id',
                type: 'ManyToOne'
              )
            end
          end
        end

        context 'with Polymorphic relation' do
          before do
            @collection_user = collection_build(
              name: 'user',
              schema: {
                fields: {
                  'id' => numeric_primary_key_build,
                  'email' => column_build,
                  'address' => Relations::PolymorphicOneToOneSchema.new(
                    origin_key: 'addressable_id',
                    foreign_collection: 'address',
                    origin_key_target: 'id',
                    origin_type_field: 'addressable_type',
                    origin_type_value: 'order'
                  )
                }
              }
            )

            @collection_address = collection_build(
              name: 'address',
              schema: {
                fields: {
                  'id' => numeric_primary_key_build,
                  'book_id' => column_build,
                  'addressable' => Relations::PolymorphicManyToOneSchema.new(
                    foreign_key_type_field: 'addressable_type',
                    foreign_collections: ['user'],
                    foreign_key_targets: { 'id' => 'user' },
                    foreign_key: 'addressable_id'
                  )
                }
              }
            )

            @datasource = described_class.new(datasource_with_collections_build([@collection_user, @collection_address]))
          end

          describe 'rename_collection' do
            it 'raise an error when collection has polymorphic relation' do
              expect { @datasource.rename_collection('user', 'renamed_user') }.to raise_error(
                Exceptions::ForestException,
                "🌳🌳🌳 Cannot rename collection user because it's a target of a polymorphic relation 'address.addressable'"
              )
            end
          end
        end
      end
    end
  end
end
