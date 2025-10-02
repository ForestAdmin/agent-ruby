require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      module Context
        module After
          include ForestAdminDatasourceToolkit

          describe HookAfterAggregateContext do
            let(:collection) { build_collection }
            let(:caller_context) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }
            let(:filter) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter) }
            let(:aggregation) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Aggregation) }
            let(:aggregate_result) { [{ 'group' => 'A', 'value' => 100 }] }
            let(:limit) { 50 }

            subject(:context) do
              described_class.new(collection, caller_context, filter, aggregation, aggregate_result, limit)
            end

            describe '#initialize' do
              it 'stores aggregate_result and inherits parent attributes' do
                expect(context.aggregate_result).to eq(aggregate_result)
                expect(context.filter).to eq(filter)
                expect(context.aggregation).to eq(aggregation)
                expect(context.limit).to eq(limit)
              end
            end

            describe 'attribute access pattern' do
              it 'does not expose standard setter' do
                expect(context).not_to respond_to(:aggregate_result=)
              end

              it 'exposes underscore-prefixed setter' do
                expect(context).to respond_to(:_aggregate_result=)
              end

              it 'allows modification via underscore setter' do
                new_result = [{ 'group' => 'B', 'value' => 200 }]
                context._aggregate_result = new_result
                expect(context.aggregate_result).to eq(new_result)
              end
            end
          end
        end
      end
    end
  end
end
