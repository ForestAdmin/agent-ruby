require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Write
      module UpdateRelations
        include ForestAdminDatasourceToolkit::Decorators
        include ForestAdminDatasourceToolkit::Schema
        include ForestAdminDatasourceToolkit::Components::Query
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
        include ForestAdminDatasourceToolkit::Exceptions

        describe UpdateRelationsCollectionDecorator do
          let(:datasource) { ForestAdminDatasourceToolkit::Datasource.new }
          let(:update_relations_datasource_decorator) { described_class }
          let(:caller) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }

          before do
            @collection_author = instance_double(
              ForestAdminDatasourceToolkit::Collection,
              name: 'author',
              schema: {
                fields: {
                  'id' => build_column(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::IN, Operators::EQUAL]),
                  'book_id' => build_column(column_type: 'Number'),
                  'first_name' => build_column,
                  'last_name' => build_column
                }
              }
            )

            @collection_book = instance_double(
              ForestAdminDatasourceToolkit::Collection,
              name: 'book',
              schema: {
                fields: {
                  'id' => build_column(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::IN, Operators::EQUAL]),
                  'author' => build_one_to_one(foreign_collection: 'author', origin_key: 'book_id'),
                  'title' => build_column
                }
              }
            )

            datasource.add_collection(@collection_author)
            datasource.add_collection(@collection_book)

            datasource_decorator = DatasourceDecorator.new(datasource, update_relations_datasource_decorator)
            @decorated_book = datasource_decorator.get_collection('book')
            @decorated_author = datasource_decorator.get_collection('author')
          end

          it 'passes the call down without changes if no relations are used' do
            allow(@collection_book).to receive(:update)
            filter = Filter.new(condition_tree: Nodes::ConditionTreeLeaf.new('title', Operators::EQUAL, 'New title'))
            patch = { 'title' => 'New title' }

            @decorated_book.update(caller, filter, patch)

            expect(@collection_book).to have_received(:update).with(caller, filter, patch)
          end

          it 'creates the related record when it does not exists' do
            allow(@collection_book).to receive(:list).and_return([{ 'id' => 1, 'author' => nil }])
            allow(@collection_book).to receive(:update)
            allow(@collection_author).to receive(:create).and_return({ 'id' => 1 })

            filter = Filter.new

            @decorated_book.update(
              caller,
              filter, {
                'title' => 'New title',
                'author' => { 'first_name' => 'John' }
              }
            )

            # Check that the decorator listed the authors to update
            expect(@collection_book).to have_received(:list).with(caller, filter, Projection.new(['author:id', 'id']))

            # Check that the normal update was made
            expect(@collection_book).to have_received(:update).with(caller, filter, { 'title' => 'New title' })

            # Check that the author was created
            expect(@collection_author).to have_received(:create).with(caller, { 'first_name' => 'John', 'book_id' => 1 })
          end

          it 'updates the related record when it exists' do
            allow(@collection_book).to receive(:list).and_return([{ 'id' => 1, 'author' => { 'id' => 1 } }])
            allow(@collection_book).to receive(:update)
            allow(@collection_author).to receive(:update)

            filter = Filter.new

            @decorated_book.update(
              caller,
              filter, {
                'title' => 'New title',
                'author' => { 'first_name' => 'John' }
              }
            )

            # Check that the decorator listed the authors to update
            expect(@collection_book).to have_received(:list).with(caller, filter, Projection.new(['author:id', 'id']))

            # Check that the update was made on both collections
            expect(@collection_book).to have_received(:update).with(caller, filter, { 'title' => 'New title' })
            expect(@collection_author).to have_received(:update) do |caller_, filter_, data|
              expect(caller_).to eq(caller)
              expect(filter_).to have_attributes(
                condition_tree: have_attributes(field: 'id', operator: Operators::EQUAL, value: 1),
                page: nil,
                search: nil,
                search_extended: nil,
                segment: nil,
                sort: nil
              )
              expect(data).to eq({ 'first_name' => 'John' })
            end
          end
        end
      end
    end
  end
end
