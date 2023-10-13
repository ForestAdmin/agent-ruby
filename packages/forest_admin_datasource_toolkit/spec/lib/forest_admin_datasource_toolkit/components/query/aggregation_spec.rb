require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Query
      include ForestAdminDatasourceToolkit::Schema
      describe Aggregation do
        it 'raise if the operation is invalid' do
          expect do
            described_class.new(operation: 'foo')
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            '🌳🌳🌳 Aggregate operation foo not allowed'
          )
        end
      end
    end
  end
end
