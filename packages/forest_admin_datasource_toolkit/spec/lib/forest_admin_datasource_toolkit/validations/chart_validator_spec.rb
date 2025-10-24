require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Validations
    describe ChartValidator do
      context 'when the condition is true' do
        it 'raises an exception' do
          expect do
            described_class.validate?(true, { key1: 1, key2: 2 }, 'key1,key2')
          end.to raise_error(ForestAdminDatasourceToolkit::Exceptions::BadRequestError,
                             "The result columns must be named 'key1,key2' instead of 'key1,key2'")
        end
      end

      context 'when the condition is false' do
        it 'returns true' do
          expect(described_class.validate?(false, { key1: 1, key2: 2 }, 'key1,key2')).to be true
        end
      end
    end
  end
end
