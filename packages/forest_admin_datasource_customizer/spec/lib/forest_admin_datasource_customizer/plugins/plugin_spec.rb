require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Plugins
    describe Plugin do
      let(:plugin) { described_class.new }

      describe '#run' do
        it 'raises NotImplementedError by default' do
          expect do
            plugin.run(DatasourceCustomizer.new)
          end.to raise_error(NotImplementedError, /has not implemented method 'run'/)
        end
      end
    end
  end
end
