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

    context 'when using reload!' do
      it 'reloads the stack and updates the composite datasource' do
        logger = instance_double(ForestAdminAgent::Services::LoggerService, log: nil)
        customizer = described_class.new
        stack_spy = instance_spy(ForestAdminDatasourceCustomizer::Decorators::DecoratorsStack)
        composite_before = customizer.instance_variable_get(:@composite_datasource)
        customizer.instance_variable_set(:@stack, stack_spy)

        allow(stack_spy).to receive(:reload!) do |new_composite, _logger|
          expect(new_composite).to be_a(ForestAdminDatasourceToolkit::Datasource)
        end

        allow(customizer).to receive(:datasource)
        customizer.reload!(logger: logger)

        expect(stack_spy).to have_received(:reload!).with(instance_of(ForestAdminDatasourceToolkit::Datasource), logger)
        composite_after = customizer.instance_variable_get(:@composite_datasource)
        expect(composite_after).not_to eq(composite_before)
      end

      it 'restores the old composite datasource if reload! fails' do
        logger = instance_double(ForestAdminAgent::Services::LoggerService, log: nil)
        customizer = described_class.new
        stack_spy = instance_spy(ForestAdminDatasourceCustomizer::Decorators::DecoratorsStack)

        old_composite = customizer.instance_variable_get(:@composite_datasource)
        customizer.instance_variable_set(:@stack, stack_spy)

        allow(stack_spy).to receive(:reload!).and_raise(StandardError.new('reload fail'))
        allow(customizer).to receive(:datasource)

        expect do
          customizer.reload!(logger: logger)
        end.to raise_error(StandardError, 'reload fail')

        expect(customizer.instance_variable_get(:@composite_datasource)).to eq(old_composite)
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
