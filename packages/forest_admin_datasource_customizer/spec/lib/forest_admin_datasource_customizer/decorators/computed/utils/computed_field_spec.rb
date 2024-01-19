require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Computed
      module Utils
        describe ComputedField do
          it 'transform_unique_values() should work' do
            inputs = [1, nil, 2, 2, nil, 666]
            result = described_class.transform_unique_values(
              inputs, ->(item) { item.map { |value| value * 2 } }
            )

            expect(result).to eq([2, nil, 4, 4, nil, 1332])
          end
        end
      end
    end
  end
end
