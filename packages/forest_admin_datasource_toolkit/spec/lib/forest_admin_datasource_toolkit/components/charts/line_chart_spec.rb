require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Charts
      describe LineChart do
        it 'serialize should return the correct data' do
          data = [
            { label: 'key1', values: 10 },
            { label: 'key2', values: 20 }
          ]
          chart = described_class.new(data)
          expect(chart.serialize).to eq(data)
        end
      end
    end
  end
end
