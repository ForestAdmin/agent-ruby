# frozen_string_literal: true

# rubocop:disable RSpec/VerifiedDoubleReference

require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module DSL
    describe DatasourceHelpers do
      let(:datasource_customizer) { DatasourceCustomizer.new }

      describe '#chart' do
        it 'creates a chart with the DSL syntax' do
          allow(datasource_customizer).to receive(:add_chart).with('total_users')

          datasource_customizer.chart :total_users do
            value 1234
          end

          expect(datasource_customizer).to have_received(:add_chart).with('total_users')
        end

        it 'allows symbol names' do
          allow(datasource_customizer).to receive(:add_chart).with('revenue')

          datasource_customizer.chart :revenue do
            value 5000, 4500
          end

          expect(datasource_customizer).to have_received(:add_chart).with('revenue')
        end
      end

      describe '#collection' do
        it 'customizes a collection with symbol name' do
          allow(datasource_customizer).to receive(:customize_collection).with('users', anything)

          datasource_customizer.collection :users do |c|
            # customization
          end

          expect(datasource_customizer).to have_received(:customize_collection).with('users', anything)
        end

        it 'passes the block to customize_collection' do
          block_called = false
          collection_spy = instance_double('CollectionCustomizer')
          allow(datasource_customizer).to receive(:customize_collection) do |_name, block|
            block_called = true
            block.call(collection_spy)
          end

          datasource_customizer.collection :users do |c|
            # customization
          end

          expect(block_called).to be true
        end
      end

      describe '#hide_collections' do
        it 'removes multiple collections' do
          allow(datasource_customizer).to receive(:remove_collection).with('internal', 'debug')

          datasource_customizer.hide_collections :internal, :debug

          expect(datasource_customizer).to have_received(:remove_collection).with('internal', 'debug')
        end
      end

      describe '#plugin' do
        it 'uses a plugin with options' do
          plugin_class = class_double('PluginClass')
          allow(datasource_customizer).to receive(:use).with(plugin_class, { option: 'value' })

          datasource_customizer.plugin plugin_class, option: 'value'

          expect(datasource_customizer).to have_received(:use).with(plugin_class, { option: 'value' })
        end

        it 'uses a plugin without options' do
          plugin_class = class_double('PluginClass')
          allow(datasource_customizer).to receive(:use).with(plugin_class, {})

          datasource_customizer.plugin plugin_class

          expect(datasource_customizer).to have_received(:use).with(plugin_class, {})
        end
      end
    end

    describe ChartBuilder do
      let(:context) { instance_double('ChartContext') }
      let(:result_builder) { instance_double('ResultBuilder') }
      let(:chart_builder) { described_class.new(context, result_builder) }

      describe '#value' do
        it 'returns a simple value chart' do
          allow(result_builder).to receive(:value).with(1234)

          chart_builder.value(1234)
          expect(result_builder).to have_received(:value).with(1234)
        end

        it 'returns a value chart with previous value' do
          allow(result_builder).to receive(:value).with(1234, 1000)

          chart_builder.value(1234, 1000)
          expect(result_builder).to have_received(:value).with(1234, 1000)
        end
      end

      describe '#distribution' do
        it 'returns a distribution chart' do
          data = { 'Category A' => 10, 'Category B' => 20 }
          allow(result_builder).to receive(:distribution).with(data)

          chart_builder.distribution(data)
          expect(result_builder).to have_received(:distribution).with(data)
        end
      end

      describe '#objective' do
        it 'returns an objective chart' do
          allow(result_builder).to receive(:objective).with(235, 300)

          chart_builder.objective(235, 300)
          expect(result_builder).to have_received(:objective).with(235, 300)
        end
      end

      describe '#percentage' do
        it 'returns a percentage chart' do
          allow(result_builder).to receive(:percentage).with(75.5)

          chart_builder.percentage(75.5)
          expect(result_builder).to have_received(:percentage).with(75.5)
        end
      end

      describe '#time_based' do
        it 'returns a time-based chart' do
          data = [
            { label: 'Jan', values: { sales: 100 } },
            { label: 'Feb', values: { sales: 150 } }
          ]
          allow(result_builder).to receive(:time_based).with(data)

          chart_builder.time_based(data)
          expect(result_builder).to have_received(:time_based).with(data)
        end
      end

      describe '#leaderboard' do
        it 'returns a leaderboard chart' do
          data = [
            { key: 'User 1', value: 100 },
            { key: 'User 2', value: 90 }
          ]
          allow(result_builder).to receive(:leaderboard).with(data)

          chart_builder.leaderboard(data)
          expect(result_builder).to have_received(:leaderboard).with(data)
        end
      end

      describe '#smart' do
        it 'returns a smart chart with numeric data' do
          allow(result_builder).to receive(:smart).with(1234)

          chart_builder.smart(1234)
          expect(result_builder).to have_received(:smart).with(1234)
        end

        it 'returns a smart chart with hash data' do
          data = { 'A' => 10, 'B' => 20 }
          allow(result_builder).to receive(:smart).with(data)

          chart_builder.smart(data)
          expect(result_builder).to have_received(:smart).with(data)
        end
      end

      describe '#context' do
        it 'provides access to the context' do
          expect(chart_builder.context).to eq(context)
        end
      end
    end
  end
end

# rubocop:enable RSpec/VerifiedDoubleReference
