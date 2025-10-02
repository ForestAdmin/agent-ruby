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

      describe 'attribute access' do
        describe '#caller' do
          it 'returns the caller' do
            expect(context.caller).to eq(caller_context)
          end
        end

        describe '#caller=' do
          it 'does not exist (raises NoMethodError)' do
            new_caller = instance_double(ForestAdminDatasourceToolkit::Components::Caller)
            expect { context.caller = new_caller }.to raise_error(NoMethodError, /caller=/)
          end
        end

        describe '#_caller=' do
          it 'allows setting caller with underscore prefix' do
            new_caller = instance_double(ForestAdminDatasourceToolkit::Components::Caller)
            context._caller = new_caller
            expect(context.caller).to eq(new_caller)
          end

          it 'signals advanced/cautious use with underscore prefix' do
            # This test documents the design intent: the underscore prefix
            # is a convention signaling "use with caution"
            expect(context).to respond_to(:_caller=)
            expect(context).not_to respond_to(:caller=)
          end
        end
      end
    end
  end
end
