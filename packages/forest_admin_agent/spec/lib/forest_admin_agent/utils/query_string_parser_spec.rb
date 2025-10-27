require 'spec_helper'

module ForestAdminAgent
  module Utils
    include ForestAdminDatasourceToolkit
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Components::Query
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes

    describe QueryStringParser do
      include_context 'with caller'

      describe 'parse_caller' do
        it 'return an instance of caller' do
          args = {
            headers: {
              'HTTP_AUTHORIZATION' => bearer
            },
            params: {
              'timezone' => 'America/Los_Angeles'
            }
          }

          expect(described_class.parse_caller(args)).to be_a ForestAdminDatasourceToolkit::Components::Caller
        end

        it 'raise an error if timezone is missing' do
          args = {
            headers: {
              'HTTP_AUTHORIZATION' => bearer
            },
            params: {}
          }
          expect do
            described_class.parse_caller(args)
          end.to raise_error(
            Http::Exceptions::BadRequestError,
            'Missing timezone'
          )
        end

        it 'raise an error if timezone is invalid' do
          args = {
            headers: {
              'HTTP_AUTHORIZATION' => bearer
            },
            params: {
              'timezone' => 'foo/timezone'
            }
          }
          expect do
            described_class.parse_caller(args)
          end.to raise_error(
            Http::Exceptions::BadRequestError,
            'Invalid timezone: foo/timezone'
          )
        end

        it 'raise if the user is not connected' do
          args = {
            headers: {},
            params: {
              'timezone' => 'foo/timezone'
            }
          }
          expect do
            described_class.parse_caller(args)
          end.to raise_error(
            Http::Exceptions::UnauthorizedError,
            'You must be logged in to access at this resource.'
          )
        end
      end

      describe 'parse_projection' do
        context 'when collection has PolymorphicManyToOne' do
          let(:collection) do
            datasource = Datasource.new
            collection = Collection.new(datasource, 'Address')
            collection.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'addressable_id' => ColumnSchema.new(column_type: 'Number'),
                'addressable_type' => ColumnSchema.new(column_type: 'String'),
                'addressable' => Relations::PolymorphicManyToOneSchema.new(
                  foreign_key_type_field: 'addressable_type',
                  foreign_collections: ['User'],
                  foreign_key_targets: { 'User' => 'id' },
                  foreign_key: 'addressable_id'
                )
              }
            )
            collection_user = Collection.new(datasource, 'User')
            collection_user.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'email' => ColumnSchema.new(column_type: 'String'),
                'address' => Relations::PolymorphicOneToOneSchema.new(
                  origin_key: 'addressable_id',
                  foreign_collection: 'address',
                  origin_key_target: 'id',
                  origin_type_field: 'addressable_type',
                  origin_type_value: 'User'
                )
              }
            )

            datasource.add_collection(collection)
            datasource.add_collection(collection_user)

            return collection
          end

          it 'convert the request to a valid projection with polymorphic_relation:*' do
            args = {
              params: {
                fields: { 'Address' => 'id,addressable,addressable_id,addressable_type' }
              }
            }
            expect(described_class.parse_projection(collection, args)).to eq(
              Projection.new(%w[id addressable:* addressable_id addressable_type])
            )
          end

          it 'automatically adds type field when foreign key of polymorphic relation is requested' do
            args = {
              params: {
                fields: { 'Address' => 'id,addressable_id' }
              }
            }
            expect(described_class.parse_projection(collection, args)).to eq(
              Projection.new(%w[id addressable_id addressable_type])
            )
          end

          it 'does not duplicate type field if already requested' do
            args = {
              params: {
                fields: { 'Address' => 'id,addressable_id,addressable_type' }
              }
            }
            expect(described_class.parse_projection(collection, args)).to eq(
              Projection.new(%w[id addressable_id addressable_type])
            )
          end

          it 'automatically adds type field when polymorphic relation itself is requested' do
            args = {
              params: {
                fields: { 'Address' => 'id,addressable', 'addressable' => 'id' }
              }
            }
            expect(described_class.parse_projection(collection, args)).to eq(
              Projection.new(%w[id addressable:* addressable_type])
            )
          end
        end

        context 'when request is well formed' do
          let(:collection) do
            datasource = Datasource.new
            collection_person = Collection.new(datasource, 'Person')
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
            collection = Collection.new(datasource, 'Book')
            collection.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'composite_id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'title' => ColumnSchema.new(column_type: 'String'),
                'author_id' => ColumnSchema.new(column_type: 'Number'),
                'author' => Relations::ManyToOneSchema.new(
                  foreign_key: 'author_id',
                  foreign_key_target: 'id',
                  foreign_collection: 'Person'
                )
              }
            )

            datasource.add_collection(collection)
            datasource.add_collection(collection_person)

            return collection
          end

          it 'convert the request to a valid projection' do
            args = {
              params: {
                fields: { 'Book' => 'id' }
              }
            }

            expect(described_class.parse_projection(collection, args)).to eq(Projection.new(['id']))
          end

          it 'return a projection with all the fields when the request does no contain fields' do
            args = {
              params: {
                fields: { 'Book' => '' }
              }
            }

            expect(described_class.parse_projection(collection, args)).to eq(
              Projection.new(%w[id composite_id title author_id author:id])
            )
          end

          it 'return the requested project without the primary keys when the request does not have the primary keys' do
            args = {
              params: {
                fields: { 'Book' => 'title' }
              }
            }

            expect(described_class.parse_projection(collection, args)).to eq(Projection.new(['title']))
          end

          it 'convert the request to a valid projection on a collection with relationships' do
            args = {
              params: {
                fields: {
                  'Book' => 'id, title, author',
                  'author' => 'id'
                }
              }
            }

            expect(described_class.parse_projection(collection, args)).to eq(Projection.new(%w[id title author:id]))
          end
        end
      end

      describe 'parse_projection_with_pks' do
        let(:collection) do
          datasource = Datasource.new
          collection_person = Collection.new(datasource, 'Person')
          collection_person.add_fields(
            {
              'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
              'name' => ColumnSchema.new(column_type: 'String'),
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
          collection = Collection.new(datasource, 'Book')
          collection.add_fields(
            {
              'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
              'title' => ColumnSchema.new(column_type: 'String'),
              'author_id' => ColumnSchema.new(column_type: 'Number'),
              'author' => Relations::ManyToOneSchema.new(
                foreign_key: 'author_id',
                foreign_key_target: 'id',
                foreign_collection: 'Person'
              )
            }
          )

          datasource.add_collection(collection)
          datasource.add_collection(collection_person)

          return collection
        end

        it 'return the requested project with the primary keys when the request does not contain the primary keys' do
          args = {
            params: {
              fields: { 'Book' => 'title' }
            }
          }

          expect(described_class.parse_projection_with_pks(collection, args)).to eq(Projection.new(%w[title id]))
        end

        it 'convert the request to a valid projection with pks on a collection with relationships' do
          args = {
            params: {
              fields: {
                'Book' => 'id, author',
                'author' => 'name'
              }
            }
          }

          expect(described_class.parse_projection_with_pks(collection,
                                                           args)).to eq(Projection.new(%w[id author:name author:id]))
        end
      end

      describe 'parse_pagination' do
        it 'return the pagination parameter' do
          args = {
            params: {
              page: { size: '10', number: '3' }
            }
          }

          expect(described_class.parse_pagination(args)).to have_attributes(offset: 20, limit: 10)
        end

        it 'return the default limit 15 skip 0 when request does not provide the pagination parameters' do
          expect(described_class.parse_pagination({})).to have_attributes(offset: 0, limit: 15)
        end

        it 'accept valid pagination with plus sign' do
          args = {
            params: {
              page: { size: '+50', number: '+1' }
            }
          }

          expect(described_class.parse_pagination(args)).to have_attributes(offset: 0, limit: 50)
        end

        context 'when both parameters are invalid' do
          it 'raise an error when request provides invalid values' do
            args = {
              params: {
                page: { size: -5, number: 'NaN' }
              }
            }

            expect do
              described_class.parse_pagination(args)
            end.to raise_error(
              Http::Exceptions::BadRequestError,
              'Invalid pagination [limit: -5, skip: NaN]'
            )
          end
        end

        context 'when page size is invalid but page number is valid' do
          it 'raise an error for string page size' do
            args = {
              params: {
                page: { size: 'abc', number: '1' }
              }
            }

            expect do
              described_class.parse_pagination(args)
            end.to raise_error(
              Http::Exceptions::BadRequestError,
              'Invalid pagination [limit: abc, skip: 1]'
            )
          end

          it 'raise an error for negative page size' do
            args = {
              params: {
                page: { size: '-50', number: '1' }
              }
            }

            expect do
              described_class.parse_pagination(args)
            end.to raise_error(
              Http::Exceptions::BadRequestError,
              'Invalid pagination [limit: -50, skip: 1]'
            )
          end

          it 'raise an error for zero page size' do
            args = {
              params: {
                page: { size: '0', number: '1' }
              }
            }

            expect do
              described_class.parse_pagination(args)
            end.to raise_error(
              Http::Exceptions::BadRequestError,
              'Invalid pagination [limit: 0, skip: 1]'
            )
          end

          it 'raise an error for float page size' do
            args = {
              params: {
                page: { size: '1.5', number: '1' }
              }
            }

            expect do
              described_class.parse_pagination(args)
            end.to raise_error(
              Http::Exceptions::BadRequestError,
              'Invalid pagination [limit: 1.5, skip: 1]'
            )
          end
        end

        context 'when page number is invalid but page size is valid' do
          it 'raise an error for string page number' do
            args = {
              params: {
                page: { size: '50', number: 'invalid' }
              }
            }

            expect do
              described_class.parse_pagination(args)
            end.to raise_error(
              Http::Exceptions::BadRequestError,
              'Invalid pagination [limit: 50, skip: invalid]'
            )
          end

          it 'raise an error for negative page number' do
            args = {
              params: {
                page: { size: '50', number: '-1' }
              }
            }

            expect do
              described_class.parse_pagination(args)
            end.to raise_error(
              Http::Exceptions::BadRequestError,
              'Invalid pagination [limit: 50, skip: -1]'
            )
          end

          it 'raise an error for float page number' do
            args = {
              params: {
                page: { size: '50', number: '1.5' }
              }
            }

            expect do
              described_class.parse_pagination(args)
            end.to raise_error(
              Http::Exceptions::BadRequestError,
              'Invalid pagination [limit: 50, skip: 1.5]'
            )
          end

          it 'raise an error for SQL injection attempt' do
            args = {
              params: {
                page: { size: '50', number: "'; DROP TABLE users--" }
              }
            }

            expect do
              described_class.parse_pagination(args)
            end.to raise_error(
              Http::Exceptions::BadRequestError,
              "Invalid pagination [limit: 50, skip: '; DROP TABLE users--]"
            )
          end
        end
      end

      describe 'parse_condition_tree' do
        let(:collection_category) do
          datasource = Datasource.new
          collection_category = Collection.new(datasource, 'Category')
          collection_category.add_fields(
            {
              'id' => ColumnSchema.new(column_type: 'Uuid', is_primary_key: true,
                                       filter_operators: [Operators::EQUAL]),
              'label' => ColumnSchema.new(column_type: 'String')
            }
          )

          datasource.add_collection(collection_category)

          collection_category
        end

        it 'return null when not provided' do
          expect(described_class.parse_condition_tree(collection_category, {})).to be_nil
        end

        it 'work when passed in the querystring for list' do
          args = {
            params: {
              filters: '{"aggregator":"And","conditions": [{"field":"id","operator":"equal","value":"123e4567-e89b-12d3-a456-426614174000"}]}'
            }
          }

          expect(described_class.parse_condition_tree(collection_category, args)).to have_attributes(
            field: 'id', operator: 'equal', value: '123e4567-e89b-12d3-a456-426614174000'
          )
        end

        it 'works when passed in the body for actions' do
          args = {
            params: {
              data: {
                attributes: {
                  all_records_subset_query: {
                    filters: '{"field":"id","operator":"equal","value":"123e4567-e89b-12d3-a456-426614174000"}'
                  }
                }
              }
            }
          }

          expect(described_class.parse_condition_tree(collection_category, args)).to have_attributes(
            field: 'id', operator: 'equal', value: '123e4567-e89b-12d3-a456-426614174000'
          )
        end

        it 'throw an error when the operator is not allowed' do
          args = {
            params: {
              filters: '{"aggregator":"And","conditions": [{"field":"id","operator":"NotEqual","value":"123e4567-e89b-12d3-a456-426614174000"}]}'
            }
          }

          expect do
            described_class.parse_condition_tree(collection_category, args)
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ValidationError,
            "The given operator 'not_equal' is not supported by the column: 'id'. The column is not filterable"
          )
        end
      end

      describe 'when parse_search' do
        let(:collection_category) do
          datasource = Datasource.new
          collection_category = Collection.new(datasource, 'Category')
          collection_category.add_fields(
            {
              'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                       filter_operators: [Operators::EQUAL]),
              'label' => ColumnSchema.new(column_type: 'String')
            }
          )

          datasource.add_collection(collection_category)

          return collection_category
        end

        let(:collection_user) do
          datasource = Datasource.new
          collection_user = Collection.new(datasource, 'User')
          collection_user.add_fields(
            {
              'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                       filter_operators: [Operators::EQUAL]),
              'name' => ColumnSchema.new(column_type: 'String')
            }
          )
          collection_user.schema[:searchable] = true

          datasource.add_collection(collection_user)

          return collection_user
        end

        it 'returns null when not provided' do
          args = { params: {} }

          expect(described_class.parse_search(collection_category, args)).to be_nil
        end

        it 'throws an error when the collection is not searchable' do
          args = { params: { search: 'searched argument' } }

          expect do
            described_class.parse_search(collection_category, args)
          end.to raise_error(
            Http::Exceptions::BadRequestError,
            'Collection is not searchable'
          )
        end

        it 'returns the query search parameter' do
          args = { params: { search: 'searched argument' } }

          expect(described_class.parse_search(collection_user, args)).to eq('searched argument')
        end

        it 'converts the query search parameter as string' do
          args = { params: { search: 1234 } }

          expect(described_class.parse_search(collection_user, args)).to eq(1234)
        end

        it 'works when passed in the body (actions)' do
          args = {
            params: {
              data: {
                attributes: {
                  all_records_subset_query: {
                    search: 'searched argument'
                  }
                }
              }
            }
          }

          expect(described_class.parse_search(collection_user, args)).to eq('searched argument')
        end
      end

      describe 'when parse_search_extended' do
        it 'returns the query searchExtended parameter' do
          args = { params: { searchExtended: true } }

          expect(described_class.parse_search_extended(args)).to be(true)
        end

        it 'returns false for falsy "0" string' do
          args = { params: { searchExtended: '0' } }

          expect(described_class.parse_search_extended(args)).to be(false)
        end
      end

      describe 'parse_sort' do
        let(:collection_user) do
          datasource = Datasource.new
          collection_user = Collection.new(datasource, 'User')
          collection_user.add_fields(
            {
              'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                       filter_operators: [Operators::EQUAL]),
              'name' => ColumnSchema.new(column_type: 'String')
            }
          )

          datasource.add_collection(collection_user)

          return collection_user
        end

        it 'sorts by pk ascending when not sort is given' do
          args = {
            params: {}
          }

          expect(described_class.parse_sort(collection_user, args)).to eq([{ field: 'id', ascending: true }])
        end

        it 'sorts by the request field and order when given' do
          args = {
            params: {
              sort: '-name'
            }
          }

          expect(described_class.parse_sort(collection_user, args)).to eq([{ field: 'name', ascending: false }])
        end

        it 'throws a ValidationError when the requested sort is invalid' do
          args = {
            params: {
              sort: '-fieldThatDoNotExist'
            }
          }

          expect do
            described_class.parse_sort(collection_user, args)
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ValidationError,
            "Column not found: 'User.fieldThatDoNotExist'"
          )
        end

        describe 'when sending multiple sort' do
          it 'returns the sort clauses' do
            args = {
              params: {
                sort: 'name,-id'
              }
            }

            expect(described_class.parse_sort(collection_user, args)).to eq([{ field: 'name', ascending: true }, { field: 'id', ascending: false }])
          end

          it 'throws a ValidationError when one of the sorting field is invalid' do
            args = {
              params: {
                sort: 'name,-fieldThatDoesNotExist'
              }
            }

            expect do
              described_class.parse_sort(collection_user, args)
            end.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ValidationError,
              'Column not found: \'User.fieldThatDoesNotExist\''
            )
          end
        end
      end

      describe 'parse_export_pagination' do
        it 'returns a Page with offset 0 and the given limit when limit is provided' do
          page = described_class.parse_export_pagination(100)

          expect(page.offset).to eq(0)
          expect(page.limit).to eq(100)
        end

        it 'returns a Page with offset 0 and nil limit when no limit is provided' do
          page = described_class.parse_export_pagination(nil)

          expect(page.offset).to eq(0)
          expect(page.limit).to be_nil
        end
      end
    end
  end
end
