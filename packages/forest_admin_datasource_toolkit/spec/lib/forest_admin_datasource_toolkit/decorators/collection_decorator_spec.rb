require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Decorators
    describe CollectionDecorator do
      before do
        datasource = Datasource.new
        @collection_book = collection_build(
          name: 'book',
          schema: {
            fields: {
              'id' => ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(column_type: 'Number', is_primary_key: true),
              'title' => ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(column_type: 'String')
            }
          }
        )

        datasource.add_collection(@collection_book)
      end

      context 'when native_driver is called' do
        it 'returns the native driver' do
          allow(@collection_book).to receive(:native_driver).and_return('a native driver')

          expect(@collection_book.native_driver).to eq('a native driver')
        end
      end
    end
  end
end
