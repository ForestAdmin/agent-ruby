require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Decorators
    describe DatasourceDecorator do
      context 'when build_binding_symbol is called' do
        it 'forwards to the child datasource' do
          child_datasource = instance_double(Datasource)
          decorator = described_class.new(child_datasource, CollectionDecorator)

          allow(child_datasource).to receive(:build_binding_symbol).with('primary', { '$1' => 1 }).and_return('$2')

          expect(decorator.build_binding_symbol('primary', { '$1' => 1 })).to eq('$2')
        end
      end
    end
  end
end
