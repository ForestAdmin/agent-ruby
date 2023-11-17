require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Charts
      describe SmartChart do
        it 'serialize should return the correct data' do
          chart = described_class.new([{ label: 'smart', value: 'chart' }])
          expect(chart.serialize).to eq([{ label: 'smart', value: 'chart' }])
        end
      end
    end
  end
end
