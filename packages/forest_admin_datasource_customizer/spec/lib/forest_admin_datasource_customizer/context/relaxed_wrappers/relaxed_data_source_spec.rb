require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Context
    module RelaxedWrappers
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Schema

      describe RelaxedDataSource do
        include_context 'with caller'

        let(:wrapped_collection) { instance_double(RelaxedCollection) }

        before do
          @datasource = Datasource.new
          @collection = build_collection(
            name: 'book',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'title' => ColumnSchema.new(column_type: 'String')
              }
            }
          )
          @datasource.add_collection(@collection)

          allow(RelaxedCollection).to receive(:new).with(@collection, caller).and_return(wrapped_collection)
        end

        it 'wraps the collection using RelaxedCollection with caller' do
          relaxed = described_class.new(@datasource, caller)

          result = relaxed.get_collection('book')

          expect(result).to eq(wrapped_collection)
          expect(RelaxedCollection).to have_received(:new).with(@collection, caller)
        end
      end
    end
  end
end
