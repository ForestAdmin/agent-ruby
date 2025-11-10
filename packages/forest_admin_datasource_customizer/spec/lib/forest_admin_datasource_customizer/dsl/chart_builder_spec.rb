# frozen_string_literal: true

# rubocop:disable RSpec/VerifiedDoubleReference

require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module DSL
    describe ChartBuilder do
      let(:context) { instance_spy('ChartContext') }
      let(:result_builder) { instance_spy('ResultBuilder') }
      let(:chart_builder) { described_class.new(context, result_builder) }

      describe '#initialize' do
        it 'stores context and result_builder' do
          expect(chart_builder.context).to eq(context)
        end
      end

      describe '#value' do
        it 'calls result_builder.value with single value' do
          chart_builder.value(100)
          expect(result_builder).to have_received(:value).with(100)
        end

        it 'calls result_builder.value with current and previous values' do
          chart_builder.value(100, 90)
          expect(result_builder).to have_received(:value).with(100, 90)
        end
      end

      describe '#distribution' do
        it 'calls result_builder.distribution with data' do
          data = { 'A' => 10, 'B' => 20 }
          chart_builder.distribution(data)
          expect(result_builder).to have_received(:distribution).with(data)
        end
      end

      describe '#objective' do
        it 'calls result_builder.objective with current and target' do
          chart_builder.objective(235, 300)
          expect(result_builder).to have_received(:objective).with(235, 300)
        end
      end

      describe '#percentage' do
        it 'calls result_builder.percentage with value' do
          chart_builder.percentage(75.5)
          expect(result_builder).to have_received(:percentage).with(75.5)
        end
      end

      describe '#time_based' do
        it 'calls result_builder.time_based with data' do
          data = [
            { label: 'Jan', values: { sales: 100 } },
            { label: 'Feb', values: { sales: 150 } }
          ]
          chart_builder.time_based(data)
          expect(result_builder).to have_received(:time_based).with(data)
        end
      end

      describe '#leaderboard' do
        it 'calls result_builder.leaderboard with data' do
          data = [
            { key: 'User 1', value: 100 },
            { key: 'User 2', value: 90 }
          ]
          chart_builder.leaderboard(data)
          expect(result_builder).to have_received(:leaderboard).with(data)
        end
      end

      describe '#smart' do
        it 'calls result_builder.smart with data' do
          data = { 'A' => 10, 'B' => 20 }
          chart_builder.smart(data)
          expect(result_builder).to have_received(:smart).with(data)
        end
      end
    end
  end
end

# rubocop:enable RSpec/VerifiedDoubleReference
