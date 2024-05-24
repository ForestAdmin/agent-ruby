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
        customized.stack.apply_queued_customizations({})

        expect(customized.collections).to be_empty
      end
    end

    context 'when rename a collection' do
      it 'rename the collection into the datasource' do
        customized = described_class.new
                                    .add_datasource(
                                      datasource,
                                      {
                                        rename: { 'collection' => 'renamed_collection' }
                                      }
                                    )
        customized.stack.apply_queued_customizations({})

        expect(customized.collections.key?('renamed_collection')).to be(true)
      end
    end

    context 'when using add_chart' do
      it 'add a chart' do
        customizer = described_class.new
        definition = proc { |_context, result_builder| result_builder.value(10) }
        customizer.add_chart('my_chart', &definition)
        datasource = customizer.datasource({})

        expect(datasource.schema[:charts]).to include('my_chart')
        expect(datasource.render_chart(caller, 'my_chart')).to eq({ countCurrent: 10, countPrevious: nil })
      end
    end

    context 'when using a plugin' do
      it 'adds a plugin' do
        customizer = described_class.new
        customizer.add_datasource(datasource, {})
        plugin = instance_double(plugin)
        allow(plugin).to receive(:new).and_return(plugin)
        allow(plugin).to receive(:run).with(customizer, nil, { my_options: 1 })

        customizer.use(plugin, { my_options: 1 })
        customizer.datasource({})
        expect(plugin).to have_received(:run).with(customizer, nil, { my_options: 1 })
      end
    end
  end
end
