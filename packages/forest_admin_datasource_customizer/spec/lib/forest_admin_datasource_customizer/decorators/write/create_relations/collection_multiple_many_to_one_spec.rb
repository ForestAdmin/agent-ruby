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
                  'id' => column_build(column_type: 'Uuid'),
                  'title' => column_build,
                  'author_id' => column_build(column_type: 'Number'),
                  'my_author' => many_to_one_build(foreign_collection: 'author', foreign_key: 'author_id'),
                  'format_id' => column_build(column_type: 'Number'),
                  'my_format' => many_to_one_build(foreign_collection: 'format', foreign_key: 'format_id')
                }
              }
            )

            @collection_author = instance_double(
              ForestAdminDatasourceToolkit::Collection,
              name: 'author',
              schema: {
                fields: {
                  'id' => column_build(column_type: 'Uuid'),
                  'name' => column_build,
                  'price_id' => column_build(column_type: 'Number')
                }
              }
            )

            @collection_format = instance_double(
              ForestAdminDatasourceToolkit::Collection,
              name: 'format',
              schema: {
                fields: {
                  'id' => column_build(column_type: 'Number'),
                  'name' => column_build
                }
              }
            )

            datasource.add_collection(@collection_book)
            datasource.add_collection(@collection_author)
            datasource.add_collection(@collection_format)

            datasource_decorator = write_datasource_decorator.new(datasource)
            @decorated_book = datasource_decorator.get_collection('book')
            @decorated_author = datasource_decorator.get_collection('author')
            @decorated_format = datasource_decorator.get_collection('format')
          end

          it 'creates the relations and attaches to the new collection' do
            allow(@collection_book).to receive(:create).and_return({ 'id' => '1', 'title' => 'name' })
            allow(@collection_author).to receive(:create).and_return({ 'id' => '1', 'name' => 'Orius' })
            allow(@collection_format).to receive(:create).and_return({ 'id' => '1', 'name' => 'XXL' })

            @decorated_book.replace_field_writing('title') do
              {
                'my_author' => { 'name' => 'Orius' },
                'my_format' => { 'name' => 'XXL' },
                'title' => 'name'
              }
            end

            @decorated_book.create(caller, { 'title' => 'a title' })

            expect(@collection_author).to have_received(:create).with(caller, { 'name' => 'Orius' })
            expect(@collection_format).to have_received(:create).with(caller, { 'name' => 'XXL' })
            expect(@collection_book).to have_received(:create).with(caller, { 'title' => 'name', 'format_id' => '1', 'author_id' => '1' })
          end
        end
      end
    end
  end
end
