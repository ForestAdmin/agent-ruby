require 'spec_helper'

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
            @collection_price = instance_double(
              ForestAdminDatasourceToolkit::Collection,
              name: 'price',
              schema: {
                fields: {
                  'id' => build_column(column_type: 'Uuid', is_primary_key: true, filter_operators: [Operators::IN, Operators::EQUAL]),
                  'value' => build_column(column_type: 'Number')
                }
              }
            )

            @collection_person = instance_double(
              ForestAdminDatasourceToolkit::Collection,
              name: 'person',
              schema: {
                fields: {
                  'id' => build_column(column_type: 'Uuid', is_primary_key: true, filter_operators: [Operators::IN, Operators::EQUAL]),
                  'name' => build_column,
                  'price_id' => build_column(column_type: 'Uuid'),
                  'my_price' => build_many_to_one(foreign_collection: 'price', foreign_key: 'price_id')
                }
              }
            )

            @collection_book = instance_double(
              ForestAdminDatasourceToolkit::Collection,
              name: 'book',
              schema: {
                fields: {
                  'id' => build_column(column_type: 'Uuid', is_primary_key: true, filter_operators: [Operators::IN, Operators::EQUAL]),
                  'title' => build_column,
                  'author_id' => build_column(column_type: 'Uuid'),
                  'my_author' => build_many_to_one(foreign_collection: 'person', foreign_key: 'author_id')
                }
              }
            )

            datasource.add_collection(@collection_price)
            datasource.add_collection(@collection_person)
            datasource.add_collection(@collection_book)

            datasource_decorator = write_datasource_decorator.new(datasource)
            @decorated_book = datasource_decorator.get_collection('book')
            @decorated_person = datasource_decorator.get_collection('person')
            @decorated_price = datasource_decorator.get_collection('price')
          end

          it 'updates the right relation collection with the right params' do
            @decorated_book.replace_field_writing('title') do
              {
                'my_author' => { 'name' => 'NAME TO CHANGE' }
              }
            end

            allow(@collection_book).to receive(:list).and_return([
                                                                   { 'id' => '123e4567-aaaa-12d3-a456-111111111111', 'my_author' => { 'id' => '123e4567-e89b-12d3-a456-111111111111' } },
                                                                   { 'id' => '123e4567-bbbb-12d3-a456-222222222222', 'my_author' => { 'id' => '123e4567-e89b-12d3-a456-222222222222' } }
                                                                 ])
            allow(@collection_person).to receive(:update)

            @decorated_book.update(caller, Filter.new, { 'title' => 'a title' })

            expect(@collection_book).to have_received(:list) do |context_caller, _filter, projection|
              expect(context_caller).to eq caller
              expect(projection).to eq Projection.new(%w[id my_author:id])
            end

            expect(@collection_person).to have_received(:update) do |context_caller, filter, data|
              expect(context_caller).to eq caller
              expect(filter).to have_attributes(
                condition_tree: have_attributes(field: 'id', operator: Operators::IN, value: ['123e4567-e89b-12d3-a456-111111111111', '123e4567-e89b-12d3-a456-222222222222']),
                page: nil,
                search: nil,
                search_extended: nil,
                segment: nil,
                sort: nil
              )
              expect(data).to eq({ 'name' => 'NAME TO CHANGE' })
            end
          end

          it 'updates a 2 degree relation' do
            @decorated_book.replace_field_writing('title') do
              {
                'my_author' => { 'my_price' => { 'value' => 10 } }
              }
            end

            allow(@collection_book).to receive(:list).and_return([
                                                                   { 'id' => '123e4567-aaaa-12d3-a456-111111111111', 'my_author' => { 'id' => '123e4567-e89b-12d3-a456-111111111111' } }
                                                                 ])
            allow(@collection_person).to receive(:list).and_return([
                                                                     { 'id' => '123e4567-e89b-12d3-a456-111111111111', 'my_price' => { 'id' => '123e4567-e89b-12d3-a456-333333333333' } }
                                                                   ])
            allow(@collection_price).to receive(:update)

            @decorated_book.update(caller, Filter.new, { 'title' => 'a title' })

            expect(@collection_book).to have_received(:list) do |_caller, _filter, projection|
              expect(projection).to eq Projection.new(%w[id my_author:id])
            end

            expect(@collection_person).to have_received(:list) do |_caller, filter, projection|
              expect(filter).to have_attributes(
                condition_tree: have_attributes(field: 'id', operator: Operators::EQUAL, value: '123e4567-e89b-12d3-a456-111111111111'),
                page: nil,
                search: nil,
                search_extended: nil,
                segment: nil,
                sort: nil
              )
              expect(projection).to eq Projection.new(%w[id my_price:id])
            end

            expect(@collection_price).to have_received(:update) do |_caller, filter, data|
              expect(filter).to have_attributes(
                condition_tree: have_attributes(field: 'id', operator: Operators::EQUAL, value: '123e4567-e89b-12d3-a456-333333333333'),
                page: nil,
                search: nil,
                search_extended: nil,
                segment: nil,
                sort: nil
              )
              expect(data).to eq({ 'value' => 10 })
            end
          end

          it 'creates the relation and attaches to the new collection' do
            @decorated_book.replace_field_writing('title') do
              {
                'my_author' => { 'name' => 'NAME TO CHANGE' }
              }
            end

            allow(@collection_book).to receive(:create).and_return({ 'title' => 'name' })
            allow(@collection_person).to receive(:create).and_return({ 'id' => '123e4567-e89b-12d3-a456-111111111111', 'name' => 'NAME TO CHANGE' })

            @decorated_book.create(caller, { 'title' => 'a title' })

            expect(@collection_book).to have_received(:create) do |context_caller, data|
              expect(context_caller).to eq caller
              expect(data).to eq({ 'author_id' => '123e4567-e89b-12d3-a456-111111111111' })
            end

            expect(@collection_person).to have_received(:create) do |context_caller, data|
              expect(context_caller).to eq caller
              expect(data).to eq({ 'name' => 'NAME TO CHANGE' })
            end
          end

          it 'updates the relation and attaches to the new collection' do
            @decorated_book.replace_field_writing('title') do
              {
                'my_author' => { 'name' => 'NAME TO CHANGE' }
              }
            end

            allow(@collection_book).to receive(:create).and_return({ 'title' => 'name' })
            allow(@collection_person).to receive(:update)

            @decorated_book.create(caller, { 'title' => 'a title', 'author_id' => '123e4567-e89b-12d3-a456-111111111111' })

            expect(@collection_book).to have_received(:create) do |context_caller, data|
              expect(context_caller).to eq caller
              expect(data).to eq({ 'author_id' => '123e4567-e89b-12d3-a456-111111111111' })
            end

            expect(@collection_person).to have_received(:update) do |context_caller, filter, data|
              expect(context_caller).to eq caller
              expect(filter).to have_attributes(
                condition_tree: have_attributes(field: 'id', operator: Operators::EQUAL, value: '123e4567-e89b-12d3-a456-111111111111'),
                page: nil,
                search: nil,
                search_extended: nil,
                segment: nil,
                sort: nil
              )
              expect(data).to eq({ 'name' => 'NAME TO CHANGE' })
            end
          end
        end
      end
    end
  end
end
