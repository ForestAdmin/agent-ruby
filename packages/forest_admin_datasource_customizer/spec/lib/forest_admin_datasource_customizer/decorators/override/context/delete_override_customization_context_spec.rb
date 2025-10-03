require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Override
      module Context
        include ForestAdminDatasourceToolkit

        describe DeleteOverrideCustomizationContext do
          let(:collection) { build_collection }
          let(:caller_context) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }
          let(:filter) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter) }

          subject(:context) { described_class.new(collection, caller_context, filter) }

          describe '#initialize' do
            it 'stores filter' do
              expect(context.filter).to eq(filter)
            end

            it 'inherits from CollectionCustomizationContext' do
              expect(context).to be_a(ForestAdminDatasourceCustomizer::Context::CollectionCustomizationContext)
            end
          end

          describe 'attribute access pattern' do
            describe '#filter' do
              it 'provides read access' do
                expect(context.filter).to eq(filter)
              end
            end

            describe '#filter=' do
              it 'does not exist (raises NoMethodError)' do
                new_filter = instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter)
                expect { context.filter = new_filter }.to raise_error(NoMethodError, /filter=/)
              end
            end

            describe '#_filter=' do
              it 'allows setting filter with underscore prefix' do
                new_filter = instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter)
                context._filter = new_filter
                expect(context.filter).to eq(new_filter)
              end

              it 'signals advanced/cautious use with underscore prefix' do
                expect(context).to respond_to(:_filter=)
                expect(context).not_to respond_to(:filter=)
              end
            end
          end
        end
      end
    end
  end
end
