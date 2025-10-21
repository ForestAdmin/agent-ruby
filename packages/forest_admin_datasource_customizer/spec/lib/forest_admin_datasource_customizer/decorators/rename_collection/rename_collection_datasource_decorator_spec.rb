require 'spec_helper'

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
          datasource = build_datasource_with_collections(
            [build_collection(name: 'foo', schema: { fields: { 'id' => build_numeric_primary_key } })]
          )
          decorated_datasource = described_class.new(datasource)
          collection = decorated_datasource.get_collection('foo')

          expect(collection.name).to eq('foo')
        end

        it 'return the new name when it is renamed' do
          datasource = build_datasource_with_collections(
            [build_collection(name: 'foo', schema: { fields: { 'id' => build_numeric_primary_key } })]
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
            @collection_library = build_collection(
              name: 'library',
              schema: {
                fields: {
                  'id' => build_numeric_primary_key,
                  'many_to_many_relation' => build_many_to_many(
                    foreign_collection: 'book',
                    origin_key: 'library_id',
                    through_collection: 'library_book',
                    foreign_key: 'book_id'
                  )
                }
              }
            )

            @collection_library_book = build_collection(
              name: 'library_book',
              schema: {
                fields: {
                  'book_id' => build_numeric_primary_key,
                  'library_id' => build_numeric_primary_key,
                  'my_book' => build_many_to_one(foreign_collection: 'book', foreign_key: 'book_id'),
                  'my_library' => build_many_to_one(foreign_collection: 'library', foreign_key: 'library_id')
                }
              }
            )

            @collection_book = build_collection(
              name: 'book',
              schema: {
                fields: {
                  'id' => build_numeric_primary_key,
                  'many_to_many_relation' => build_many_to_many(
                    foreign_collection: 'library',
                    origin_key: 'book_id',
                    through_collection: 'library_book',
                    foreign_key: 'library_id'
                  )
                }
              }
            )

            @datasource = described_class.new(
              build_datasource_with_collections(
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
                "The given new collection name 'book' is already defined"
              )
            end

            it 'raise an error if renaming twice' do
              @datasource.rename_collection('book', 'book2')
              expect do
                @datasource.rename_collection('book2', 'book3')
              end.to raise_error(
                Exceptions::ForestException,
                'Cannot rename a collection twice: book->book2->book3'
              )
            end

            it 'raise an error if the given old name does not exist' do
              expect do
                @datasource.rename_collection('doesNotExist', 'book')
              end.to raise_error(
                Exceptions::ForestException,
                'Collection doesNotExist not found.'
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
              @datasource.rename_collections({})

              expect(@datasource.collections.keys).to include('library_book')
            end

            it 'work when using a hash' do
              @datasource.rename_collections({ 'library_book' => 'renamed_library_book' })
              collection_name = @datasource.collections.map { |_key, collection| collection.name }

              expect(collection_name).to include('renamed_library_book')
            end

            it 'renames collection using a function' do
              @datasource.rename_collections(->(name) { name == 'library_book' ? 'renamed_library_book' : name })
              collection_name = @datasource.collections.map { |_key, collection| collection.name }

              expect(collection_name).to include('renamed_library_book')
            end

            it 'renames collection using a function returning null' do
              @datasource.rename_collections(->(name) { name == 'library_book' ? 'renamed_library_book' : nil })
              collection_name = @datasource.collections.map { |_key, collection| collection.name }

              expect(collection_name).to include('library')
              expect(collection_name).to include('renamed_library_book')
              expect(collection_name).to include('book')
            end

            it 'raise an error if the argument is not a function or a hash' do
              expect do
                @datasource.rename_collections('not a function')
              end.to raise_error(
                ForestAdminDatasourceToolkit::Exceptions::ForestException,
                'Invalid argument for rename_collections, must be a function or a hash'
              )
            end
          end
        end

        context 'with OneToOne relation' do
          before do
            @collection_book = build_collection(
              name: 'book',
              schema: {
                fields: {
                  'id' => build_numeric_primary_key,
                  'owner' => build_one_to_one(foreign_collection: 'owner', origin_key: 'book_id')
                }
              }
            )

            @collection_owner = build_collection(
              name: 'owner',
              schema: {
                fields: {
                  'id' => build_numeric_primary_key,
                  'book_id' => build_column,
                  'owner' => build_many_to_one(foreign_collection: 'owner', foreign_key: 'book_id')
                }
              }
            )

            @datasource = described_class.new(build_datasource_with_collections([@collection_book, @collection_owner]))
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
            @collection_book = build_collection(
              name: 'book',
              schema: {
                fields: {
                  'id' => build_numeric_primary_key,
                  'person_id' => build_column,
                  'my_person' => build_many_to_one(foreign_collection: 'person', foreign_key: 'person_id')
                }
              }
            )

            @collection_person = build_collection(
              name: 'person',
              schema: {
                fields: {
                  'id' => build_numeric_primary_key,
                  'name' => build_column,
                  'my_books' => build_one_to_many(foreign_collection: 'book', origin_key: 'id')
                }
              }
            )

            @datasource = described_class.new(build_datasource_with_collections([@collection_book, @collection_person]))
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
            @collection_user = build_collection(
              name: 'user',
              schema: {
                fields: {
                  'id' => build_numeric_primary_key,
                  'email' => build_column,
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

            @collection_address = build_collection(
              name: 'address',
              schema: {
                fields: {
                  'id' => build_numeric_primary_key,
                  'book_id' => build_column,
                  'addressable' => Relations::PolymorphicManyToOneSchema.new(
                    foreign_key_type_field: 'addressable_type',
                    foreign_collections: ['user'],
                    foreign_key_targets: { 'user' => 'id' },
                    foreign_key: 'addressable_id'
                  )
                }
              }
            )

            @datasource = described_class.new(build_datasource_with_collections([@collection_user, @collection_address]))
          end

          describe 'rename_collection' do
            it 'raise an error when collection has polymorphic relation' do
              expect { @datasource.rename_collection('user', 'renamed_user') }.to raise_error(
                Exceptions::ForestException,
                "Cannot rename collection user because it's a target of a polymorphic relation 'address.addressable'"
              )
            end
          end
        end
      end
    end
  end
end
