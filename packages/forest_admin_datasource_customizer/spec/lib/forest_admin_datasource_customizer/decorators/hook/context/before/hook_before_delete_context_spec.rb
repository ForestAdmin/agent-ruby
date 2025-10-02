require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      module Context
        module Before
          include ForestAdminDatasourceToolkit

          describe HookBeforeDeleteContext do
            let(:collection) { build_collection }
            let(:caller_context) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }
            let(:filter) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter) }

            subject(:context) { described_class.new(collection, caller_context, filter) }

            describe '#initialize' do
              it 'stores filter' do
                expect(context.filter).to eq(filter)
              end
            end

            describe 'attribute access pattern' do
              it 'does not expose standard setter' do
                expect(context).not_to respond_to(:filter=)
              end

              it 'exposes underscore-prefixed setter' do
                expect(context).to respond_to(:_filter=)
              end

              it 'allows modification via underscore setter' do
                new_filter = instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter)
                context._filter = new_filter
                expect(context.filter).to eq(new_filter)
              end
            end
          end
        end
      end
    end
  end
end
