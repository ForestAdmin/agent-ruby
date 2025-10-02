require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      module Context
        module After
          include ForestAdminDatasourceToolkit

          describe HookAfterListContext do
            let(:collection) { build_collection }
            let(:caller_context) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }
            let(:filter) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter) }
            let(:projection) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Projection) }
            let(:records) { [{ 'id' => 1, 'name' => 'Record 1' }, { 'id' => 2, 'name' => 'Record 2' }] }

            subject(:context) { described_class.new(collection, caller_context, filter, projection, records) }

            describe '#initialize' do
              it 'stores records and inherits parent attributes' do
                expect(context.records).to eq(records)
                expect(context.filter).to eq(filter)
                expect(context.projection).to eq(projection)
              end
            end

            describe 'attribute access pattern' do
              it 'does not expose standard setter' do
                expect(context).not_to respond_to(:records=)
              end

              it 'exposes underscore-prefixed setter' do
                expect(context).to respond_to(:_records=)
              end

              it 'allows modification via underscore setter' do
                new_records = [{ 'id' => 3, 'name' => 'Modified' }]
                context._records = new_records
                expect(context.records).to eq(new_records)
              end
            end
          end
        end
      end
    end
  end
end
