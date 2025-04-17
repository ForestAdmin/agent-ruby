require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Context
    describe AgentCustomizationContext do
      let(:datasource) { instance_double(ForestAdminDatasourceToolkit::Datasource) }
      let(:caller_context) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }

      let(:relaxed_data_source_class) do
        class_spy(ForestAdminDatasourceCustomizer::Context::RelaxedWrappers::RelaxedDataSource)
      end

      subject(:context) { described_class.new(datasource, caller_context) }

      before do
        stub_const(
          'ForestAdminDatasourceCustomizer::Context::RelaxedWrappers::RelaxedDataSource',
          relaxed_data_source_class
        )
      end

      describe '#initialize' do
        it 'stores the real datasource and caller' do
          expect(context.instance_variable_get(:@real_datasource)).to eq(datasource)
          expect(context.caller).to eq(caller_context)
        end
      end

      describe '#datasource' do
        it 'instantiates a RelaxedDataSource with correct arguments' do
          context.datasource # ← appel réel

          expect(relaxed_data_source_class)
            .to have_received(:new)
            .with(datasource, caller_context)
        end
      end
    end
  end
end
