require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Charts
      describe ValueChart do
        context 'when previous_value is not defined' do
          it 'serialize should return the correct data with nil value for countPrevious' do
            chart = described_class.new(10)

            expect(chart.serialize).to eq({ countCurrent: 10, countPrevious: nil })
          end
        end

        context 'when previous_value is defined' do
          it 'serialize should return the correct data' do
            chart = described_class.new(10, 5)

            expect(chart.serialize).to eq({ countCurrent: 10, countPrevious: 5 })
          end
        end
      end
    end
  end
end
