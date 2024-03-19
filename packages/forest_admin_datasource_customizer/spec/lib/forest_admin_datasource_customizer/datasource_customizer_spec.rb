require 'spec_helper'

module ForestAdminDatasourceCustomizer
  include ForestAdminDatasourceToolkit::Schema

  describe DatasourceCustomizer do
    let(:datasource) { ForestAdminDatasourceToolkit::Datasource.new }

    before do
      @collection = instance_double(
        ForestAdminDatasourceToolkit::Collection,
        name: 'collection',
        schema: {
          fields: {
            'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true)
          }
        }
      )

      datasource.add_collection(@collection)
    end

    context 'when removing a collection' do
      it 'removes the collection into the datasource' do
        customized = described_class.new
                                    .add_datasource(datasource, {})
                                    .remove_collection('collection')

        expect(customized.collections).to be_empty
      end
    end
  end
end
