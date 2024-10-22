require 'spec_helper'

module ForestAdminAgent
  module Utils
    module Schema
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Schema
      describe GeneratorField do
        before do
          @datasource = Datasource.new
          collection_book = Collection.new(@datasource, 'Book')
          collection_book.add_fields(
            {
              'isbn' => ColumnSchema.new(
                column_type: 'String',
                is_primary_key: true,
                filter_operators: %w[Equal NotEqual Present],
                is_sortable: true,
                is_read_only: true,
                validations: [{ operator: Operators::PRESENT }]
              ),
              'origin_key' => ColumnSchema.new(
                column_type: 'Number',
                is_primary_key: false,
                is_sortable: false,
                is_read_only: false
              ),
              'composite' => ColumnSchema.new(
                column_type: { firstname: 'String', lastname: 'String' }
              ),
              'array_of_composite' => ColumnSchema.new(
                column_type: [{ firstname: 'String', lastname: 'String' }]
              )
            }
          )

          @datasource.add_collection(collection_book)
        end

        it 'generate the proper schema for the isbn field' do
          schema = described_class.build_schema(@datasource.get_collection('Book'), 'isbn')

          expect(schema).to match(
            {
              field: 'isbn',
              type: 'String',
              isSortable: true,
              inverseOf: nil,
              defaultValue: nil,
              enums: [],
              integration: nil,
              isFilterable: true,
              isPrimaryKey: true,
              isReadOnly: true,
              isRequired: false,
              isVirtual: false,
              reference: nil,
              validations: [{ message: 'Field is required', type: 'is present' }]
            }
          )
        end

        it 'generate the proper schema for the other field' do
          schema = described_class.build_schema(@datasource.get_collection('Book'), 'origin_key')

          expect(schema).to match(
            {
              field: 'origin_key',
              type: 'Number',
              isSortable: false,
              inverseOf: nil,
              defaultValue: nil,
              enums: [],
              integration: nil,
              isFilterable: false,
              isPrimaryKey: false,
              isReadOnly: false,
              isRequired: false,
              isVirtual: false,
              reference: nil,
              validations: []
            }
          )
        end

        it 'generate the proper schema for composite types' do
          schema = described_class.build_schema(@datasource.get_collection('Book'), 'composite')

          expect(schema[:type]).to match(
            {
              fields: [
                { field: :firstname, type: 'String' },
                { field: :lastname, type: 'String' }
              ]
            }
          )
        end

        it 'generate the proper schema for array of composites types' do
          schema = described_class.build_schema(@datasource.get_collection('Book'), 'array_of_composite')

          expect(schema[:type]).to match(
            [
              {
                fields: [
                  { field: :firstname, type: 'String' },
                  { field: :lastname, type: 'String' }
                ]
              }
            ]
          )
        end
      end
    end
  end
end
