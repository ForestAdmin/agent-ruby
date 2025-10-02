require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      module Context
        module After
          include ForestAdminDatasourceToolkit

          describe HookAfterCreateContext do
            let(:collection) { build_collection }
            let(:caller_context) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }
            let(:data) { { 'name' => 'New Item' } }
            let(:record) { { 'id' => 123, 'name' => 'New Item' } }

            subject(:context) { described_class.new(collection, caller_context, data, record) }

            describe '#initialize' do
              it 'stores record and inherits data from parent' do
                expect(context.record).to eq(record)
                expect(context.data).to eq(data)
              end
            end

            describe 'attribute access pattern' do
              it 'does not expose standard setter' do
                expect(context).not_to respond_to(:record=)
              end

              it 'exposes underscore-prefixed setter' do
                expect(context).to respond_to(:_record=)
              end

              it 'allows modification via underscore setter' do
                new_record = { 'id' => 456, 'name' => 'Modified' }
                context._record = new_record
                expect(context.record).to eq(new_record)
              end
            end
          end
        end
      end
    end
  end
end
