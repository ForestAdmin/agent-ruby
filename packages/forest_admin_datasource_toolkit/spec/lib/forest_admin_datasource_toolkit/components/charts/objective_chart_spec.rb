require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Charts
      describe ObjectiveChart do
        context 'when objective is not defined' do
          it 'serialize should return the correct data without objective' do
            chart = described_class.new(10)

            expect(chart.serialize).to eq({ value: 10 })
          end
        end

        context 'when objective is defined' do
          it 'serialize should return the correct data with objective' do
            chart = described_class.new(10, 20)

            expect(chart.serialize).to eq({ value: 10, objective: 20 })
          end
        end
      end
    end
  end
end
