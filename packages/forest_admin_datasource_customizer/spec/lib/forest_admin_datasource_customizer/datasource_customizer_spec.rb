require 'spec_helper'

module ForestAdminDatasourceCustomizer
  include ForestAdminDatasourceToolkit::Schema
  include ForestAdminAgent::Http::Exceptions

  describe DatasourceCustomizer do
    let(:datasource) { ForestAdminDatasourceToolkit::Datasource.new }

    before do
      @collection = instance_double(
        ForestAdminDatasourceToolkit::Collection,
        name: 'collection',
        schema: {
          fields: {
            'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true)
          },
          countable: false,
          searchable: false,
          charts: [],
          segments: [],
          actions: {}
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

    context 'when using get_root_datasource_by_connection' do
      it 'raise an error when connection is unknown' do
        datasource_customizer = described_class.new

        expect do
          datasource_customizer.get_root_datasource_by_connection('unknown_connection')
        end.to raise_error(NotFoundError, "Native query connection 'unknown_connection' is unknown.")
      end

      it 'return the expected datasource' do
        datasource_customizer = described_class.new
        first_datasource = build_datasource(live_query_connections: { 'primary' => 'primary' })
        second_datasource = build_datasource(live_query_connections: { 'replica' => 'replica' })
        datasource_customizer.add_datasource(first_datasource, {})
        datasource_customizer.add_datasource(second_datasource, {})

        expect(datasource_customizer.get_root_datasource_by_connection('primary'))
          .to eq(first_datasource)
      end
    end
  end
end
