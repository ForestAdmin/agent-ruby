require 'spec_helper'
require 'shared/caller'

module ForestAdminDatasourceCustomizer
  module Context
    module RelaxedWrappers
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Decorators
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      describe RelaxedCollection do
        include_context 'with caller'
        subject(:relaxed_collection) { described_class }
        let(:compute_collection_decorator) { ForestAdminDatasourceCustomizer::Decorators::Computed::ComputeCollectionDecorator }

        before do
          datasource = Datasource.new
          @collection_book = collection_build(
            name: 'book',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'title' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::LONGER_THAN, Operators::PRESENT])
              }
            }
          )

          datasource.add_collection(@collection_book)
          datasource_decorator = DatasourceDecorator.new(datasource, compute_collection_decorator)

          @new_books = datasource_decorator.get_collection('book')
        end

        context 'when native_driver is called' do
          it 'returns the native driver' do
            allow(@new_books).to receive(:native_driver).and_return('a native driver')
            relaxed_collection = described_class.new(@new_books, caller)

            expect(relaxed_collection.native_driver).to eq('a native driver')
          end
        end

        context 'when schema is called' do
          it 'returns the schema' do
            allow(@new_books).to receive(:schema).and_return({ fields: { 'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true) } })
            relaxed_collection = described_class.new(@new_books, caller)

            expect(relaxed_collection.schema).to be_instance_of(Hash)
            expect(relaxed_collection.schema).to include(:fields)
            expect(relaxed_collection.schema[:fields]).to have_key('id')
          end
        end
      end
    end
  end
end
