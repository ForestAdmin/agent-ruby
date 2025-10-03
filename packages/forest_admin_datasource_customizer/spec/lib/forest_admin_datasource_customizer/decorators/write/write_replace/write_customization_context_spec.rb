require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Write
      module WriteReplace
        include ForestAdminDatasourceToolkit

        describe WriteCustomizationContext do
          let(:collection) { build_collection }
          let(:caller_context) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }
          let(:action) { 'create' }
          let(:record) { { 'id' => 1, 'name' => 'Test' } }
          let(:filter) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter) }

          subject(:context) { described_class.new(collection, caller_context, action, record, filter) }

          describe '#initialize' do
            it 'stores action, record, and filter' do
              expect(context.action).to eq(action)
              expect(context.record).to eq(record)
              expect(context.filter).to eq(filter)
            end

            it 'inherits from CollectionCustomizationContext' do
              expect(context).to be_a(ForestAdminDatasourceCustomizer::Context::CollectionCustomizationContext)
            end
          end

          describe 'attribute access pattern' do
            it 'does not expose standard setters' do
              expect(context).not_to respond_to(:action=)
              expect(context).not_to respond_to(:record=)
              expect(context).not_to respond_to(:filter=)
            end

            it 'exposes underscore-prefixed setters' do
              expect(context).to respond_to(:_action=)
              expect(context).to respond_to(:_record=)
              expect(context).to respond_to(:_filter=)
            end

            it 'allows modification via underscore setters' do
              new_action = 'update'
              new_record = { 'id' => 2, 'name' => 'Modified' }
              new_filter = instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter)

              context._action = new_action
              context._record = new_record
              context._filter = new_filter

              expect(context.action).to eq(new_action)
              expect(context.record).to eq(new_record)
              expect(context.filter).to eq(new_filter)
            end
          end
        end
      end
    end
  end
end
