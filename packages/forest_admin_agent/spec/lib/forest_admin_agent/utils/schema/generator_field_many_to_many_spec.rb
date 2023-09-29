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
                'reviewers' => Relations::ManyToManySchema.new(
                  origin_key: 'book_id',
                  origin_key_target: 'id',
                  foreign_collection: 'Person',
                  foreign_key: 'person_id',
                  foreign_key_target: 'id',
                  through_collection: 'BookPerson'
                )
              }
            )

            collection_book_person = Collection.new(@datasource, 'BookPerson')
            collection_book_person.add_fields(
              {
                'person_id' => ColumnSchema.new(column_type: 'Number', is_read_only: true),
                'person' => Relations::ManyToOneSchema.new(
                  foreign_key: 'person_id',
                  foreign_key_target: 'id',
                  foreign_collection: 'Person'
                ),
                'book_id' => ColumnSchema.new(column_type: 'Number', is_read_only: true),
                'book' => Relations::ManyToOneSchema.new(
                  foreign_key: 'book_id',
                  foreign_key_target: 'id',
                  foreign_collection: 'Book'
                )
              }
            )

            collection_person = Collection.new(@datasource, 'Person')
            collection_person.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'books' => Relations::ManyToManySchema.new(
                  origin_key: 'person_id',
                  origin_key_target: 'id',
                  foreign_collection: 'Book',
                  foreign_key: 'book_id',
                  foreign_key_target: 'id',
                  through_collection: 'BookPerson'
                )
              }
            )

            @datasource.add_collection(collection_book)
            @datasource.add_collection(collection_book_person)
            @datasource.add_collection(collection_person)
          end

          it 'generate relation' do
            schema = described_class.build_schema(@datasource.collection('Book'), 'reviewers')

            expect(schema).to match(
              {
                field: 'reviewers',
                inverseOf: nil,
                reference: 'Person.id',
                relationship: 'BelongsToMany',
                type: ['Number'],
                defaultValue: nil,
                enums: nil,
                integration: nil,
                isFilterable: false,
                isPrimaryKey: false,
                isReadOnly: true,
                isRequired: false,
                isSortable: true,
                isVirtual: false,
                validations: {}
              }
            )
          end

          it 'sort schema property' do
            schema = described_class.build_schema(@datasource.collection('Book'), 'reviewers')

            expect(schema.keys).to eq(
              [
                :defaultValue,
                :enums,
                :field,
                :integration,
                :inverseOf,
                :isFilterable,
                :isPrimaryKey,
                :isReadOnly,
                :isRequired,
                :isSortable,
                :isVirtual,
                :reference,
                :relationship,
                :type,
                :validations
              ]
            )
          end

          context 'when the field reference is the primary key' do
            it 'the many to one relation should not be a primary key' do
              schema = described_class.build_schema(@datasource.collection('BookPerson'), 'book')
              expect(schema).to match(
                {
                  field: 'book',
                  inverseOf: nil,
                  reference: 'Book.id',
                  relationship: 'BelongsTo',
                  type: 'Number',
                  defaultValue: nil,
                  enums: nil,
                  integration: nil,
                  isFilterable: true,
                  isPrimaryKey: false,
                  isReadOnly: true,
                  isRequired: false,
                  isSortable: false,
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
end
