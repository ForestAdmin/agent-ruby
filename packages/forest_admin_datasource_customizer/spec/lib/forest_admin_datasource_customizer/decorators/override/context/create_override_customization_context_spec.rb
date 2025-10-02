require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Override
      module Context
        include ForestAdminDatasourceToolkit

        describe CreateOverrideCustomizationContext do
          let(:collection) { build_collection }
          let(:caller_context) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }
          let(:data) { { 'name' => 'New Record', 'status' => 'active' } }

          subject(:context) { described_class.new(collection, caller_context, data) }

          describe '#initialize' do
            it 'stores data' do
              expect(context.data).to eq(data)
            end

            it 'inherits from CollectionCustomizationContext' do
              expect(context).to be_a(ForestAdminDatasourceCustomizer::Context::CollectionCustomizationContext)
            end
          end

          describe 'attribute access pattern' do
            describe '#data' do
              it 'provides read access' do
                expect(context.data).to eq(data)
              end
            end

            describe '#data=' do
              it 'does not exist (raises NoMethodError)' do
                expect { context.data = {} }.to raise_error(NoMethodError, /data=/)
              end
            end

            describe '#_data=' do
              it 'allows setting data with underscore prefix' do
                new_data = { 'modified' => 'value' }
                context._data = new_data
                expect(context.data).to eq(new_data)
              end

              it 'signals advanced/cautious use with underscore prefix' do
                expect(context).to respond_to(:_data=)
                expect(context).not_to respond_to(:data=)
              end
            end
          end
        end
      end
    end
  end
end
