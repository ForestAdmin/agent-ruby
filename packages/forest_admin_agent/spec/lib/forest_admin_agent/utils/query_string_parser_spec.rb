require 'spec_helper'
require 'shared/caller'

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
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            '🌳🌳🌳 Missing timezone'
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
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            '🌳🌳🌳 Invalid timezone: foo/timezone'
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
            Http::Exceptions::HttpException,
            'You must be logged in to access at this resource.'
          )
        end
      end

      describe 'parse_projection' do
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

        context 'when request is well formed' do
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

        it 'raise an error when request provides invalid values' do
          args = {
            params: {
              page: { size: -5, number: 'NaN' }
            }
          }

          expect do
            described_class.parse_pagination(args)
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            '🌳🌳🌳 Invalid pagination [limit: -5, skip: NaN]'
          )
        end
      end

      describe 'parse_condition_tree' do
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

          collection_category
        end

        it 'return null when not provided' do
          expect(described_class.parse_condition_tree(collection_category, {})).to be_nil
        end

        it 'work when passed in the querystring for list' do
          args = {
            params: {
              filters: '{"aggregator":"And","conditions": [{"field":"id","operator":"Equal","value":"123e4567-e89b-12d3-a456-426614174000"}]}'
            }
          }

          expect(described_class.parse_condition_tree(collection_category, args)).eql?(
            ConditionTreeLeaf.new('id', 'Equal', '123e4567-e89b-12d3-a456-426614174000')
          )
        end

        it 'works when passed in the body for charts' do
          args = {
            params: {
              data: {
                attributes: {
                  all_records_subset_query: {
                    filters: '{"field":"id","operator":"Equal","value":"123e4567-e89b-12d3-a456-426614174000"}'
                  }
                }
              }
            }
          }

          expect(described_class.parse_condition_tree(collection_category, args)).eql?(
            ConditionTreeLeaf.new('id', 'Equal', '123e4567-e89b-12d3-a456-426614174001')
          )
        end

        it 'works when passed in the body for actions' do
          args = {
            params: {
              data: {
                attributes: {
                  all_records_subset_query: {
                    filters: '{"field":"id","operator":"Equal","value":"123e4567-e89b-12d3-a456-426614174000"}'
                  }
                }
              }
            }
          }

          expect(described_class.parse_condition_tree(collection_category, args)).eql?(
            ConditionTreeLeaf.new('id', 'Equal', '123e4567-e89b-12d3-a456-426614174000')
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
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            '🌳🌳🌳 Collection is not searchable'
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
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            "🌳🌳🌳 Column not found: 'User.fieldThatDoNotExist'"
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
              ForestAdminDatasourceToolkit::Exceptions::ForestException,
              '🌳🌳🌳 Column not found: \'User.fieldThatDoesNotExist\''
            )
          end
        end
      end
    end
  end
end
