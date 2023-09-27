require 'spec_helper'

module ForestAdminAgent
  module Utils
    module Schema
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Schema
      describe GeneratorField do
        context 'when field is OneToMany relation' do
          before do
            @datasource = Datasource.new
            collection_book = Collection.new(@datasource, 'Book')
            collection_book.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'author_id' => ColumnSchema.new(column_type: 'Number', is_read_only: true, is_sortable: true),
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
                'written_books' => Relations::OneToManySchema.new(
                  origin_key: 'author_id',
                  origin_key_target: 'id',
                  foreign_collection: 'Book'
                )
              }
            )

            @datasource.add_collection(collection_book)
            @datasource.add_collection(collection_person)
          end

          it 'generate relation' do
            schema = described_class.build_schema(@datasource.collection('Book'), 'author')

            expect(schema).to match(
              {
                field: 'author',
                inverseOf: nil,
                reference: 'Person.id',
                relationship: 'BelongsTo',
                type: 'Number',
                defaultValue: nil,
                enums: nil,
                integration: nil,
                isFilterable: true,
                isPrimaryKey: false,
                isReadOnly: true,
                isRequired: false,
                isSortable: true,
                isVirtual: false,
                validations: {}
              }
            )
          end

          it 'generate inverse relation' do
            schema = described_class.build_schema(@datasource.collection('Person'), 'written_books')

            expect(schema).to match(
              {
                field: 'written_books',
                inverseOf: nil,
                reference: 'Book.id',
                relationship: 'HasMany',
                type: ['Number'],
                isSortable: true,
                defaultValue: nil,
                enums: nil,
                integration: nil,
                isFilterable: false,
                isPrimaryKey: false,
                isReadOnly: true,
                isRequired: false,
                isVirtual: false,
                validations: {}
              }
            )
          end
        end
      end
    end
  end
end
