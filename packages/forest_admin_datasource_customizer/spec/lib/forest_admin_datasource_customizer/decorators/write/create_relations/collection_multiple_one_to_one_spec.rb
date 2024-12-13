require 'spec_helper'
require 'shared/caller'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Write
      module WriteReplace
        include ForestAdminDatasourceToolkit::Schema
        include ForestAdminDatasourceToolkit::Components::Query
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
                  'id' => build_column(column_type: 'Number'),
                  'title' => build_column,
                  'my_owner' => build_one_to_one(foreign_collection: 'owner', origin_key: 'book_id'),
                  'my_format' => build_one_to_one(foreign_collection: 'format', origin_key: 'book_id')
                }
              }
            )

            @collection_owner = instance_double(
              ForestAdminDatasourceToolkit::Collection,
              name: 'owner',
              schema: {
                fields: {
                  'id' => build_column(column_type: 'Number'),
                  'name' => build_column,
                  'book_id' => build_column(column_type: 'Number')
                }
              }
            )

            @collection_format = instance_double(
              ForestAdminDatasourceToolkit::Collection,
              name: 'format',
              schema: {
                fields: {
                  'id' => build_column(column_type: 'Number'),
                  'name' => build_column,
                  'book_id' => build_column(column_type: 'Number')
                }
              }
            )

            datasource.add_collection(@collection_book)
            datasource.add_collection(@collection_owner)
            datasource.add_collection(@collection_format)

            datasource_decorator = write_datasource_decorator.new(datasource)
            @decorated_book = datasource_decorator.get_collection('book')
            @decorated_owner = datasource_decorator.get_collection('owner')
            @decorated_format = datasource_decorator.get_collection('format')
          end

          it 'creates the relations and attaches to the new collection' do
            allow(@collection_book).to receive(:create).and_return({ 'id' => '1', 'title' => 'name' })
            allow(@collection_owner).to receive(:create).and_return({ 'book_id' => '1', 'name' => 'Orius' })
            allow(@collection_format).to receive(:create).and_return({ 'book_id' => '1', 'name' => 'XXL' })

            @decorated_book.replace_field_writing('title') do
              {
                'my_owner' => { 'name' => 'Orius' },
                'my_format' => { 'name' => 'XXL' },
                'title' => 'name'
              }
            end

            @decorated_book.create(caller, { 'title' => 'a title' })

            expect(@collection_book).to have_received(:create).with(caller, { 'title' => 'name' })
            expect(@collection_owner).to have_received(:create).with(caller, { 'name' => 'Orius', 'book_id' => '1' })
            expect(@collection_format).to have_received(:create).with(caller, { 'name' => 'XXL', 'book_id' => '1' })
          end
        end
      end
    end
  end
end
