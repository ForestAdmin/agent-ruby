require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Charts
      describe PercentageChart do
        it 'serialize should return the correct data' do
          expect(described_class.new(10).serialize).to eq(10)
        end
      end
    end
  end
end
