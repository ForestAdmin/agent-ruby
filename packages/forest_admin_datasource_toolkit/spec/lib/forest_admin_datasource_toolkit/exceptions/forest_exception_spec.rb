require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Exceptions
    describe ForestException do
      subject(:exception) { described_class.new 'message error' }

      it { expect(exception.message).to eq '🌳🌳🌳 message error' }
    end
  end
end
