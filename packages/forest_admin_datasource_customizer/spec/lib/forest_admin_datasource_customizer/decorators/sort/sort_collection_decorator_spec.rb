require 'spec_helper'
require 'shared/caller'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Sort
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Decorators
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Exceptions

      describe SortCollectionDecorator do
        include_context 'with caller'
        subject(:sort_collection_decorator) { described_class }

        let(:datasource) { ForestAdminDatasourceToolkit::Datasource.new }
        let(:records) do
          [
            {
              'id' => 1,
              'author_id' => 1,
              'author' => { 'id' => 1, 'first_name' => 'Isaac', 'last_name' => 'Asimov' },
              'title' => 'Foundation'
            },
            {
              'id' => 2,
              'author_id' => 2,
              'author' => { 'id' => 2, 'first_name' => 'Edward O.', 'last_name' => 'Thorp' },
              'title' => 'Beat the dealer'
            },
            {
              'id' => 3,
              'author_id' => 3,
              'author' => { 'id' => 3, 'first_name' => 'Roberto', 'last_name' => 'Saviano' },
              'title' => 'Gomorrah'
            }
          ]
        end

        before do
          @collection_book = instance_double(
            ForestAdminDatasourceToolkit::Collection,
            name: 'book',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'author_id' => ColumnSchema.new(column_type: 'String'),
                'author' => Relations::ManyToOneSchema.new(
                  foreign_key: 'author_id',
                  foreign_collection: 'person',
                  foreign_key_target: 'id'
                ),
                'title' => ColumnSchema.new(column_type: 'String', is_sortable: false)
              }
            },
            datasource: datasource
          )

          @collection_person = instance_double(
            ForestAdminDatasourceToolkit::Collection,
            name: 'person',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'first_name' => ColumnSchema.new(column_type: 'String'),
                'last_name' => ColumnSchema.new(column_type: 'String', is_sortable: false),
                'book' => Relations::OneToOneSchema.new(
                  origin_key: 'author_id',
                  origin_key_target: 'id',
                  foreign_collection: 'book'
                )
              }
            },
            datasource: datasource
          )

          allow(@collection_book).to receive(:list) do |_caller, filter, projection|
            rows = records
            rows = filter.condition_tree.apply(rows, @collection_book, 'Europe/Paris') if filter.condition_tree
            rows = filter.sort.apply(rows) if filter.sort
            rows = filter.page.apply(rows) if filter.page

            projection.apply(rows)
          end

          datasource.add_collection(@collection_book)
          datasource.add_collection(@collection_person)

          datasource_decorator = ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator.new(datasource, sort_collection_decorator)

          @decorated_book = datasource_decorator.get_collection('book')
          @decorated_person = datasource_decorator.get_collection('person')
        end

        it 'emulate_field_sorting() should throw if the field does not exists' do
          expect { @decorated_book.emulate_field_sorting('__dontExist') }.to raise_error(ValidationError, "🌳🌳🌳 Column not found: 'book.__dontExist'")
        end

        it 'emulate_field_sorting() should throw if the field is not sortable' do
          expect { @decorated_book.emulate_field_sorting('author') }.to raise_error(ValidationError, "🌳🌳🌳 Unexpected field type: 'book.author' (found 'ManyToOne' expected 'Column')")
        end

        it 'replace_field_sorting() should throw if no equivalent_sort is provided' do
          expect { @decorated_book.replace_field_sorting('author_id', nil) }.to raise_error(ForestException, '🌳🌳🌳 A new sorting method should be provided to replace field sorting')
        end

        context 'when emulating sort on book.title (no relations)' do
          before do
            @decorated_book.emulate_field_sorting('title')
          end

          it 'schema should be updated' do
            schema = @decorated_book.schema[:fields]['title']
            expect(schema.is_sortable).to be_truthy
          end

          it 'works in ascending order' do
            records = @decorated_book.list(
              caller,
              Filter.new(sort: ForestAdminDatasourceToolkit::Components::Query::Sort.new([{ field: 'title', ascending: true }])),
              Projection.new(%w[id title])
            )
            expect(records).to eq([
                                    { 'id' => 2, 'title' => 'Beat the dealer' },
                                    { 'id' => 1, 'title' => 'Foundation' },
                                    { 'id' => 3, 'title' => 'Gomorrah' }
                                  ])
          end

          it 'works in descending order' do
            records = @decorated_book.list(
              caller,
              Filter.new(sort: ForestAdminDatasourceToolkit::Components::Query::Sort.new([{ field: 'title', ascending: false }])),
              Projection.new(%w[id title])
            )
            expect(records).to eq([
                                    { 'id' => 3, 'title' => 'Gomorrah' },
                                    { 'id' => 1, 'title' => 'Foundation' },
                                    { 'id' => 2, 'title' => 'Beat the dealer' }
                                  ])
          end

          it 'works with pagination' do
            records = @decorated_book.list(
              caller,
              Filter.new(page: Page.new(offset: 2, limit: 1), sort: ForestAdminDatasourceToolkit::Components::Query::Sort.new([{ field: 'title', ascending: false }])),
              Projection.new(%w[id title])
            )
            expect(records).to eq([{ 'id' => 2, 'title' => 'Beat the dealer' }])
          end
        end

        context 'when emulating sort on book.author.last_name (relation)' do
          before do
            @decorated_person.emulate_field_sorting('last_name')
          end

          it 'schema should be updated' do
            schema = @decorated_person.schema[:fields]['last_name']
            expect(schema.is_sortable).to be_truthy
          end

          it 'works in ascending order' do
            records = @decorated_book.list(
              caller,
              Filter.new(sort: ForestAdminDatasourceToolkit::Components::Query::Sort.new([{ field: 'author:last_name', ascending: true }])),
              Projection.new(%w[id title author:last_name])
            )
            expect(records).to eq([
                                    { 'id' => 1, 'title' => 'Foundation', 'author' => { 'last_name' => 'Asimov' } },
                                    { 'id' => 3, 'title' => 'Gomorrah', 'author' => { 'last_name' => 'Saviano' } },
                                    { 'id' => 2, 'title' => 'Beat the dealer', 'author' => { 'last_name' => 'Thorp' } }
                                  ])
          end

          it 'works in descending order' do
            records = @decorated_book.list(
              caller,
              Filter.new(sort: ForestAdminDatasourceToolkit::Components::Query::Sort.new([{ field: 'author:last_name', ascending: false }])),
              Projection.new(%w[id title author:last_name])
            )

            expect(records).to eq([
                                    { 'id' => 2, 'title' => 'Beat the dealer', 'author' => { 'last_name' => 'Thorp' } },
                                    { 'id' => 3, 'title' => 'Gomorrah', 'author' => { 'last_name' => 'Saviano' } },
                                    { 'id' => 1, 'title' => 'Foundation', 'author' => { 'last_name' => 'Asimov' } }
                                  ])
          end
        end

        context 'when telling that sort(book.title) = sort(book.author.last_name)' do
          before do
            @decorated_book.replace_field_sorting('title', ForestAdminDatasourceToolkit::Components::Query::Sort.new([{ field: 'author:last_name', ascending: true }]))
          end

          it 'schema should be updated' do
            schema = @decorated_book.schema[:fields]['title']
            expect(schema.is_sortable).to be_truthy
          end

          it 'works in ascending order' do
            records = @decorated_book.list(
              caller,
              Filter.new(sort: ForestAdminDatasourceToolkit::Components::Query::Sort.new([{ field: 'title', ascending: true }])),
              Projection.new(%w[id title author:last_name])
            )
            expect(records).to eq([
                                    { 'id' => 1, 'title' => 'Foundation', 'author' => { 'last_name' => 'Asimov' } },
                                    { 'id' => 3, 'title' => 'Gomorrah', 'author' => { 'last_name' => 'Saviano' } },
                                    { 'id' => 2, 'title' => 'Beat the dealer', 'author' => { 'last_name' => 'Thorp' } }
                                  ])
          end

          it 'works in descending order' do
            records = @decorated_book.list(
              caller,
              Filter.new(sort: ForestAdminDatasourceToolkit::Components::Query::Sort.new([{ field: 'title', ascending: false }])),
              Projection.new(%w[id title author:last_name])
            )
            expect(records).to eq([
                                    { 'id' => 2, 'title' => 'Beat the dealer', 'author' => { 'last_name' => 'Thorp' } },
                                    { 'id' => 3, 'title' => 'Gomorrah', 'author' => { 'last_name' => 'Saviano' } },
                                    { 'id' => 1, 'title' => 'Foundation', 'author' => { 'last_name' => 'Asimov' } }
                                  ])
          end
        end
      end
    end
  end
end
