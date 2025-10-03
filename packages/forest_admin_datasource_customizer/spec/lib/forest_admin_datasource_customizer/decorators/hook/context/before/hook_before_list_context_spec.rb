require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      module Context
        module Before
          include ForestAdminDatasourceToolkit

          describe HookBeforeListContext do
            let(:collection) { build_collection }
            let(:caller_context) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }
            let(:filter) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter) }
            let(:projection) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Projection) }

            subject(:context) { described_class.new(collection, caller_context, filter, projection) }

            describe '#initialize' do
              it 'stores filter and projection' do
                expect(context.filter).to eq(filter)
                expect(context.projection).to eq(projection)
              end
            end

            describe 'attribute access pattern' do
              it 'does not expose standard setters' do
                expect(context).not_to respond_to(:filter=)
                expect(context).not_to respond_to(:projection=)
              end

              it 'exposes underscore-prefixed setters' do
                expect(context).to respond_to(:_filter=)
                expect(context).to respond_to(:_projection=)
              end

              it 'allows modification via underscore setters' do
                new_filter = instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter)
                new_projection = instance_double(ForestAdminDatasourceToolkit::Components::Query::Projection)

                context._filter = new_filter
                context._projection = new_projection

                expect(context.filter).to eq(new_filter)
                expect(context.projection).to eq(new_projection)
              end
            end
          end
        end
      end
    end
  end
end
