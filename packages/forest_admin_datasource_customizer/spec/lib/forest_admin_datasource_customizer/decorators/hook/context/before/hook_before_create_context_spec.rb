require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      module Context
        module Before
          include ForestAdminDatasourceToolkit

          describe HookBeforeCreateContext do
            let(:collection) { build_collection }
            let(:caller_context) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }
            let(:data) { { 'name' => 'New Item', 'value' => 42 } }

            subject(:context) { described_class.new(collection, caller_context, data) }

            describe '#initialize' do
              it 'stores data' do
                expect(context.data).to eq(data)
              end
            end

            describe 'attribute access pattern' do
              it 'does not expose standard setter' do
                expect(context).not_to respond_to(:data=)
              end

              it 'exposes underscore-prefixed setter' do
                expect(context).to respond_to(:_data=)
              end

              it 'allows modification via underscore setter' do
                new_data = { 'modified' => 'data' }
                context._data = new_data
                expect(context.data).to eq(new_data)
              end
            end
          end
        end
      end
    end
  end
end
