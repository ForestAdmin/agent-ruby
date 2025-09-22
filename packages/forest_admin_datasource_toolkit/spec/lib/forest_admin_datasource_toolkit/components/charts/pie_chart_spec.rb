require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Charts
      describe PieChart do
        it 'serialize should return the correct data' do
          chart = described_class.new([{ key: 'key1', value: 10 }, { key: 'key2', value: 20 }])
          expect(chart.serialize).to eq([{ key: 'key1', value: 10 }, { key: 'key2', value: 20 }])
        end
      end
    end
  end
end
