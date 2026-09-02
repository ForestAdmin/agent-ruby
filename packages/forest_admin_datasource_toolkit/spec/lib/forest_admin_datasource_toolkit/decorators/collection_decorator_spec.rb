require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Decorators
    describe CollectionDecorator do
      before do
        datasource = Datasource.new
        @collection_book = build_collection(
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

      # The permission layer probes this with `respond_to?` on the top of a 26-layer stack, so a
      # missing link answers "no customization" instead of raising. Owned here, tested here.
      context 'when search_handler? is called' do
        it 'forwards to the child decorator, which is where the search layer answers' do
          child = described_class.new(@collection_book, @collection_book.datasource)
          allow(child).to receive(:search_handler?).and_return(true)
          decorator = described_class.new(child, @collection_book.datasource)

          expect(decorator.search_handler?).to be true
        end

        it 'answers false at the bottom, where the child is a plain collection' do
          decorator = described_class.new(@collection_book, @collection_book.datasource)

          expect(decorator.search_handler?).to be false
        end
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
