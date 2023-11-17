require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Charts
      describe LeaderboardChart do
        it 'serialize should return the correct data' do
          data = [
            { key: 'key1', value: 10 },
            { key: 'key2', value: 20 }
          ]
          chart = described_class.new(data)
          expect(chart.serialize).to eq(data)
        end
      end
    end
  end
end
