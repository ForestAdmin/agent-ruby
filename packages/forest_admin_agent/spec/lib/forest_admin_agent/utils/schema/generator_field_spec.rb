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
                validation: [{ operator: Operators::PRESENT }]
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

        context 'when relation has missing fields' do
          before do
            @datasource_with_bad_relations = Datasource.new

            collection_order = Collection.new(@datasource_with_bad_relations, 'Order')
            collection_order.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                # user_id field is missing but relation references it
                'user' => Relations::ManyToOneSchema.new(
                  foreign_key: 'missing_user_id',
                  foreign_key_target: 'id',
                  foreign_collection: 'User'
                )
              }
            )

            collection_user = Collection.new(@datasource_with_bad_relations, 'User')
            collection_user.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'name' => ColumnSchema.new(column_type: 'String')
              }
            )

            @datasource_with_bad_relations.add_collection(collection_order)
            @datasource_with_bad_relations.add_collection(collection_user)
          end

          it 'returns nil and logs a warning when foreign_key field is missing in ManyToOne relation' do
            logger = instance_spy(Logger)
            allow(Facades::Container).to receive(:logger).and_return(logger)

            schema = described_class.build_schema(
              @datasource_with_bad_relations.get_collection('Order'),
              'user'
            )

            expect(schema).to be_nil
            expect(logger).to have_received(:log).with(
              'Warn',
              "Field 'missing_user_id' (foreign_key) not found in collection 'Order' for relation 'user'. " \
              'This relation will be skipped. Check if the field exists in your database.'
            )
          end
        end

        context 'when OneToMany relation has missing origin_key' do
          before do
            @datasource_with_bad_one_to_many = Datasource.new

            collection_author = Collection.new(@datasource_with_bad_one_to_many, 'Author')
            collection_author.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'books' => Relations::OneToManySchema.new(
                  origin_key: 'missing_author_id',
                  origin_key_target: 'id',
                  foreign_collection: 'Book'
                )
              }
            )

            collection_book = Collection.new(@datasource_with_bad_one_to_many, 'Book')
            collection_book.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'title' => ColumnSchema.new(column_type: 'String')
                # author_id is missing
              }
            )

            @datasource_with_bad_one_to_many.add_collection(collection_author)
            @datasource_with_bad_one_to_many.add_collection(collection_book)
          end

          it 'returns nil and logs a warning when origin_key field is missing' do
            logger = instance_spy(Logger)
            allow(Facades::Container).to receive(:logger).and_return(logger)

            schema = described_class.build_schema(
              @datasource_with_bad_one_to_many.get_collection('Author'),
              'books'
            )

            expect(schema).to be_nil
            expect(logger).to have_received(:log).with(
              'Warn',
              "Field 'missing_author_id' (origin_key) not found in collection 'Book' for relation 'books'. " \
              'This relation will be skipped. Check if the field exists in your database.'
            )
          end
        end
      end
    end
  end
end
