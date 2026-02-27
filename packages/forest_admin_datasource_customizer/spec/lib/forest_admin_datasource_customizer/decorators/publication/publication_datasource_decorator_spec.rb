require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Publication
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Exceptions

      describe PublicationDatasourceDecorator do
        before do
          datasource = ForestAdminDatasourceToolkit::Datasource.new
          @collection_library = instance_double(
            ForestAdminDatasourceToolkit::Decorators::CollectionDecorator,
            name: 'library',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'my_books' => Relations::ManyToManySchema.new(
                  origin_key: 'library_id',
                  origin_key_target: 'id',
                  foreign_key: 'book_id',
                  foreign_key_target: 'id',
                  foreign_collection: 'book',
                  through_collection: 'library_book'
                )
              }
            },
            mark_schema_as_dirty: nil
          )

          @collection_library_book = instance_double(
            ForestAdminDatasourceToolkit::Decorators::CollectionDecorator,
            name: 'library_book',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'library_id' => ColumnSchema.new(column_type: 'Number'),
                'book_id' => ColumnSchema.new(column_type: 'Number'),
                'my_library' => Relations::ManyToOneSchema.new(
                  foreign_collection: 'library',
                  foreign_key: 'library_id',
                  foreign_key_target: 'id'
                ),
                'my_book' => Relations::ManyToOneSchema.new(
                  foreign_collection: 'book',
                  foreign_key: 'book_id',
                  foreign_key_target: 'id'
                )
              }
            },
            mark_schema_as_dirty: nil
          )

          @collection_book = instance_double(
            ForestAdminDatasourceToolkit::Decorators::CollectionDecorator,
            name: 'book',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'my_libraries' => Relations::ManyToManySchema.new(
                  origin_key: 'book_id',
                  origin_key_target: 'id',
                  foreign_key: 'library_id',
                  foreign_key_target: 'id',
                  foreign_collection: 'book',
                  through_collection: 'library_book'
                )
              }
            },
            mark_schema_as_dirty: nil
          )

          @collection_user = instance_double(
            ForestAdminDatasourceToolkit::Decorators::CollectionDecorator,
            name: 'user',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'addresses' => Relations::PolymorphicOneToManySchema.new(
                  origin_key: 'addressable_id',
                  foreign_collection: 'address',
                  origin_key_target: 'id',
                  origin_type_field: 'addressable_type',
                  origin_type_value: 'address'
                )
              }
            },
            mark_schema_as_dirty: nil
          )

          @collection_address = build_collection(
            name: 'address',
            schema: {
              fields: {
                'id' => build_numeric_primary_key,
                'addressable_id' => build_column(column_type: 'Number'),
                'addressable_type' => build_column,
                'addressable' => Relations::PolymorphicManyToOneSchema.new(
                  foreign_key_type_field: 'addressable_type',
                  foreign_collections: %w[user],
                  foreign_key_targets: { 'user' => 'id' },
                  foreign_key: 'addressable_id'
                )
              }
            }
          )

          datasource.add_collection(@collection_library)
          datasource.add_collection(@collection_library_book)
          datasource.add_collection(@collection_book)
          datasource.add_collection(@collection_address)
          datasource.add_collection(@collection_user)

          datasource = ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator.new(datasource, Empty::EmptyCollectionDecorator)
          @datasource_decorator = described_class.new(datasource)

          @decorated_library = @datasource_decorator.get_collection('library')
          @decorated_library_book = @datasource_decorator.get_collection('library_book')
          @decorated_book = @datasource_decorator.get_collection('book')
        end

        it 'returns all collections when no parameter is provided' do
          expect(@decorated_library.schema).to eq(@collection_library.schema)
          expect(@decorated_library_book.schema).to eq(@collection_library_book.schema)
          expect(@decorated_book.schema).to eq(@collection_book.schema)
        end

        context 'when keep_collections_matching is called' do
          it 'throws an error if a name is unknown' do
            expect { @datasource_decorator.keep_collections_matching(['unknown']) }.to raise_error(ForestException, /Collection unknown not found\./)
            expect { @datasource_decorator.keep_collections_matching(nil, ['unknown']) }.to raise_error(ForestException, /Collection unknown not found\./)
          end

          it 'throws an error if a collection is a target of polymorphic ManyToOne' do
            expect { @datasource_decorator.keep_collections_matching(nil, ['user']) }.to raise_error(
              ForestException,
              /Cannot remove user because it's a potential target of polymorphic relation address\.addressable/
            )
          end

          it 'is able to remove "library_book" collection' do
            @datasource_decorator.keep_collections_matching(%w[library book user address])

            # expect { @datasource_decorator.get_collection('library_book') }.to raise_error(ForestException, "Collection 'library_book' was removed.")
            expect(@datasource_decorator.get_collection('library').schema[:fields]).not_to have_key('my_books')
            expect(@datasource_decorator.get_collection('book').schema[:fields]).not_to have_key('my_libraries')
          end

          it 'is able to remove "book" collection' do
            @datasource_decorator.keep_collections_matching(nil, ['book'])

            expect { @datasource_decorator.get_collection('book') }.to raise_error(ForestException, /Collection 'book' was removed\./)
            expect(@datasource_decorator.get_collection('library_book').schema[:fields]).not_to have_key('my_book')
            expect(@datasource_decorator.get_collection('library').schema[:fields]).not_to have_key('my_books')
          end
        end
      end
    end
  end
end
