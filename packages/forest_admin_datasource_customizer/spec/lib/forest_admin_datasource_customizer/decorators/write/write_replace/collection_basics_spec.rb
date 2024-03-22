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

          before do
            @collection_book = instance_double(
              ForestAdminDatasourceToolkit::Collection,
              name: 'book',
              schema: {
                fields: {
                  'name' => ColumnSchema.new(column_type: 'String', is_read_only: true)
                }
              }
            )

            datasource.add_collection(@collection_book)

            datasource_decorator = write_datasource_decorator.new(datasource)
            @decorated_book = datasource_decorator.get_collection('book')
          end

          it 'throws when rewriting an non-existent field' do
            expect { @decorated_book.replace_field_writing('__dontExist', -> { '' }) }.to raise_error(ForestException, "🌳🌳🌳 Column not found: 'book.__dontExist'")
          end

          it 'marks fields as writable when handler is defined' do
            expect(@collection_book.schema[:fields]['name'].is_read_only).to be(true)
            expect(@decorated_book.schema[:fields]['name'].is_read_only).to be(true)

            @decorated_book.replace_field_writing('name', -> {})

            expect(@collection_book.schema[:fields]['name'].is_read_only).to be(true)
            expect(@decorated_book.schema[:fields]['name'].is_read_only).to be(false)
          end

          it 'throws an error when definition is null' do
            expect(@collection_book.schema[:fields]['name'].is_read_only).to be(true)
            expect(@decorated_book.schema[:fields]['name'].is_read_only).to be(true)

            expect { @decorated_book.replace_field_writing('name', nil) }.to raise_error(ForestException, '🌳🌳🌳 A new writing method should be provided to replace field writing')
          end
        end
      end
    end
  end
end
