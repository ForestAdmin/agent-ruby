require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Override
      module Context
        include ForestAdminDatasourceToolkit

        describe UpdateOverrideCustomizationContext do
          let(:collection) { build_collection }
          let(:caller_context) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }
          let(:filter) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter) }
          let(:patch) { { 'name' => 'Updated Name', 'status' => 'inactive' } }

          subject(:context) { described_class.new(collection, caller_context, filter, patch) }

          describe '#initialize' do
            it 'stores filter and patch' do
              expect(context.filter).to eq(filter)
              expect(context.patch).to eq(patch)
            end

            it 'inherits from CollectionCustomizationContext' do
              expect(context).to be_a(ForestAdminDatasourceCustomizer::Context::CollectionCustomizationContext)
            end
          end

          describe 'attribute access pattern' do
            describe 'getters' do
              it 'provides read access to filter' do
                expect(context.filter).to eq(filter)
              end

              it 'provides read access to patch' do
                expect(context.patch).to eq(patch)
              end
            end

            describe 'standard setters (without underscore)' do
              it 'filter= does not exist' do
                expect { context.filter = nil }.to raise_error(NoMethodError, /filter=/)
              end

              it 'patch= does not exist' do
                expect { context.patch = {} }.to raise_error(NoMethodError, /patch=/)
              end
            end

            describe 'underscore-prefixed setters' do
              it 'allows setting filter with _filter=' do
                new_filter = instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter)
                context._filter = new_filter
                expect(context.filter).to eq(new_filter)
              end

              it 'allows setting patch with _patch=' do
                new_patch = { 'different' => 'data' }
                context._patch = new_patch
                expect(context.patch).to eq(new_patch)
              end

              it 'signals advanced use pattern' do
                expect(context).to respond_to(:_filter=)
                expect(context).to respond_to(:_patch=)
                expect(context).not_to respond_to(:filter=)
                expect(context).not_to respond_to(:patch=)
              end
            end
          end
        end
      end
    end
  end
end
