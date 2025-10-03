require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      module Context
        module Before
          include ForestAdminDatasourceToolkit

          describe HookBeforeAggregateContext do
            let(:collection) { build_collection }
            let(:caller_context) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }
            let(:filter) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter) }
            let(:aggregation) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Aggregation) }
            let(:limit) { 100 }

            subject(:context) { described_class.new(collection, caller_context, filter, aggregation, limit) }

            describe '#initialize' do
              it 'stores filter, aggregation, and limit' do
                expect(context.filter).to eq(filter)
                expect(context.aggregation).to eq(aggregation)
                expect(context.limit).to eq(limit)
              end
            end

            describe 'attribute access pattern' do
              it 'does not expose standard setters' do
                expect(context).not_to respond_to(:filter=)
                expect(context).not_to respond_to(:aggregation=)
                expect(context).not_to respond_to(:limit=)
              end

              it 'exposes underscore-prefixed setters' do
                expect(context).to respond_to(:_filter=)
                expect(context).to respond_to(:_aggregation=)
                expect(context).to respond_to(:_limit=)
              end

              it 'allows modification via underscore setters' do
                new_filter = instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter)
                new_aggregation = instance_double(ForestAdminDatasourceToolkit::Components::Query::Aggregation)
                new_limit = 50

                context._filter = new_filter
                context._aggregation = new_aggregation
                context._limit = new_limit

                expect(context.filter).to eq(new_filter)
                expect(context.aggregation).to eq(new_aggregation)
                expect(context.limit).to eq(new_limit)
              end
            end
          end
        end
      end
    end
  end
end
