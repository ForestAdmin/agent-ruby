require 'spec_helper'

module ForestAdminAgent
  module Utils
    module Schema
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Schema
      describe GeneratorField do
        context 'when field is OneToOne relation' do
          before do
            @datasource = Datasource.new
            collection_book = Collection.new(@datasource, 'Book')
            collection_book.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'author_id' => ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: true),
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
                'book' => Relations::OneToOneSchema.new(
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
            schema = described_class.build_schema(@datasource.get_collection('Person'), 'book')

            expect(schema).to match(
              {
                field: 'book',
                inverseOf: 'author',
                reference: 'Book.id',
                relationship: 'HasOne',
                type: 'String',
                defaultValue: nil,
                enums: nil,
                integration: nil,
                isFilterable: false,
                isPrimaryKey: false,
                isReadOnly: true,
                isRequired: false,
                isSortable: false,
                isVirtual: false,
                validations: []
              }
            )
          end

          it 'generate inverse relation' do
            schema = described_class.build_schema(@datasource.get_collection('Book'), 'author')

            expect(schema).to match(
              {
                field: 'author',
                inverseOf: 'book',
                reference: 'Person.id',
                relationship: 'BelongsTo',
                type: 'String',
                isSortable: true,
                defaultValue: nil,
                enums: nil,
                integration: nil,
                isFilterable: false,
                isPrimaryKey: false,
                isReadOnly: true,
                isRequired: false,
                isVirtual: false,
                validations: []
              }
            )
          end
        end
      end
    end
  end
end
