require 'spec_helper'
require 'shared/caller'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Write
      module WriteReplace
        include ForestAdminDatasourceToolkit::Schema
        include ForestAdminDatasourceToolkit::Components::Query
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
        include ForestAdminDatasourceToolkit::Exceptions

        describe WriteDatasourceDecorator do
          let(:datasource) { ForestAdminDatasourceToolkit::Datasource.new }
          let(:write_datasource_decorator) { described_class }
          let(:caller) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }

          before do
            @collection_book = instance_double(
              ForestAdminDatasourceToolkit::Collection,
              name: 'book',
              schema: {
                fields: {
                  'id' => column_build(column_type: 'Uuid', is_primary_key: true, filter_operators: [Operators::IN, Operators::EQUAL]),
                  'title' => column_build,
                  'my_owner' => one_to_one_build(foreign_collection: 'owner', origin_key: 'book_id')
                }
              }
            )
            @collection_owner = instance_double(
              ForestAdminDatasourceToolkit::Collection,
              name: 'owner',
              schema: {
                fields: {
                  'id' => column_build(column_type: 'Uuid', is_primary_key: true, filter_operators: [Operators::IN, Operators::EQUAL]),
                  'book_id' => column_build(column_type: 'Uuid'),
                  'name' => column_build
                }
              }
            )

            datasource.add_collection(@collection_book)
            datasource.add_collection(@collection_owner)

            datasource_decorator = write_datasource_decorator.new(datasource)
            @decorated_book = datasource_decorator.get_collection('book')
            @decorated_owner = datasource_decorator.get_collection('owner')
          end

          it 'updates the right relation collection with the right params' do
            @decorated_book.replace_field_writing('title') do
              {
                'my_owner' => { 'name' => 'NAME TO CHANGE' }
              }
            end

            allow(@collection_book).to receive(:list).and_return(
              [
                {
                  'id' => '123e4567-e89b-12d3-a456-111111111111',
                  'my_owner' => { 'id' => '123e4567-e89b-12d3-a456-000000000000' }
                }
              ]
            )
            allow(@collection_owner).to receive(:update)

            filter = Filter.new(
              condition_tree: Nodes::ConditionTreeLeaf.new('name', Operators::EQUAL, 'a name')
            )

            @decorated_book.update(caller, filter, { 'title' => 'a title' })

            expect(@collection_book).to have_received(:list) do |_caller, filter_, projection|
              expect(filter_).to have_attributes(
                condition_tree: have_attributes(field: 'name', operator: Operators::EQUAL, value: 'a name'),
                page: nil,
                search: nil,
                search_extended: nil,
                segment: nil,
                sort: nil
              )
              expect(projection).to eq Projection.new(['my_owner:id', 'id'])
            end
            expect(@collection_owner).to have_received(:update) do |_caller, filter_, data|
              expect(filter_).to have_attributes(
                condition_tree: have_attributes(field: 'id', operator: Operators::EQUAL, value: '123e4567-e89b-12d3-a456-000000000000'),
                page: nil,
                search: nil,
                search_extended: nil,
                segment: nil,
                sort: nil
              )
              expect(data).to eq({ 'name' => 'NAME TO CHANGE' })
            end
          end

          it 'creates the relation and attaches to the new collection' do
            @decorated_book.replace_field_writing('title') do
              {
                'title' => 'name',
                'my_owner' => { 'name' => 'NAME TO CHANGE' }
              }
            end

            allow(@collection_book).to receive(:create).and_return(
              { 'id' => '123e4567-e89b-12d3-a456-111111111111', 'not_important_column' => 'foo' }
            )
            allow(@collection_owner).to receive(:create)

            caller = instance_double(ForestAdminDatasourceToolkit::Components::Caller)
            @decorated_book.create(caller, { 'title' => 'a title' })

            expect(@collection_owner).to have_received(:create).with(caller, { 'name' => 'NAME TO CHANGE', 'book_id' => '123e4567-e89b-12d3-a456-111111111111' })
            expect(@collection_book).to have_received(:create).with(caller, { 'title' => 'name' })
          end
        end
      end
    end
  end
end
