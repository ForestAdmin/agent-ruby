require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Write
      module WriteReplace
        include ForestAdminDatasourceToolkit::Schema
        include ForestAdminDatasourceToolkit::Components::Query
        include ForestAdminDatasourceToolkit::Exceptions

        describe WriteReplaceCollectionDecorator do
          let(:datasource) { ForestAdminDatasourceToolkit::Datasource.new }
          let(:write_datasource_decorator) { ForestAdminDatasourceCustomizer::Decorators::Write::WriteDatasourceDecorator }
          let(:caller) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }

          before do
            @collection_author = instance_double(
              ForestAdminDatasourceToolkit::Collection,
              name: 'author',
              schema: {
                fields: {
                  'first_name' => build_column,
                  'last_name' => build_column,
                  # This field will have a rewrite rule to alias first_name
                  'first_name_alias' => build_column
                }
              }
            )

            @collection_book = instance_double(
              ForestAdminDatasourceToolkit::Collection,
              name: 'book',
              schema: {
                fields: {
                  'id' => build_numeric_primary_key,
                  'title' => build_column,
                  'author_id' => build_column(column_type: 'Number'),
                  'author' => build_many_to_one(foreign_collection: 'author', foreign_key: 'author_id'),
                  # Those fields will have rewrite handler to the corresponding author fields
                  'author_first_name' => build_column,
                  'author_last_name' => build_column
                }
              }
            )

            datasource.add_collection(@collection_book)
            datasource.add_collection(@collection_author)

            datasource_decorator = write_datasource_decorator.new(datasource)
            @decorated_book = datasource_decorator.get_collection('book')
            @decorated_author = datasource_decorator.get_collection('author')
          end

          it 'creates the related record when the relation is not set' do
            allow(@collection_book).to receive(:create).and_return({ 'id' => 1, 'title' => 'Memories', 'author_id' => 1 })
            allow(@collection_author).to receive(:create).and_return({ 'id' => 1, 'first_name' => 'John', 'last_name' => 'Doe' })

            @decorated_book.replace_field_writing('author_first_name') do |value|
              { 'author' => { 'first_name' => value } }
            end

            @decorated_book.replace_field_writing('author_last_name') do |value|
              { 'author' => { 'last_name' => value } }
            end

            @decorated_book.create(caller, { 'title' => 'Memories', 'author_first_name' => 'John', 'author_last_name' => 'Doe' })

            expect(@collection_author).to have_received(:create) do |_caller, record|
              expect(record).to eq({ 'first_name' => 'John', 'last_name' => 'Doe' })
            end
            expect(@collection_book).to have_received(:create) do |_caller, record|
              expect(record).to eq({ 'title' => 'Memories', 'author_id' => 1 })
            end
          end

          it 'calls the handlers of the related collection' do
            allow(@collection_book).to receive(:create).and_return({ 'id' => 1, 'title' => 'Memories', 'author_id' => 1 })
            allow(@collection_author).to receive(:create).and_return({ 'id' => 1, 'first_name' => 'John', 'last_name' => 'Doe' })

            @decorated_author.replace_field_writing('first_name_alias') do |value|
              { 'first_name' => value }
            end
            @decorated_book.replace_field_writing('author_first_name') do |value|
              { 'author' => { 'first_name_alias' => value } }
            end
            @decorated_book.replace_field_writing('author_last_name') do |value|
              { 'author' => { 'last_name' => value } }
            end

            @decorated_book.create(caller, { 'title' => 'Memories', 'author_first_name' => 'John', 'author_last_name' => 'Doe' })

            expect(@collection_book).to have_received(:create) do |_caller, record|
              expect(record).to eq({ 'title' => 'Memories', 'author_id' => 1 })
            end

            expect(@collection_author).to have_received(:create) do |_caller, record|
              expect(record).to eq({ 'first_name' => 'John', 'last_name' => 'Doe' })
            end
          end
        end
      end
    end
  end
end
