require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      module Context
        module Before
          include ForestAdminDatasourceToolkit

          describe HookBeforeUpdateContext do
            let(:collection) { build_collection }
            let(:caller_context) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }
            let(:filter) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter) }
            let(:patch) { { 'name' => 'New Name', 'status' => 'active' } }

            subject(:context) { described_class.new(collection, caller_context, filter, patch) }

            describe '#initialize' do
              it 'stores filter and patch' do
                expect(context.filter).to eq(filter)
                expect(context.patch).to eq(patch)
              end

              it 'inherits from HookContext' do
                expect(context).to be_a(Hook::Context::HookContext)
              end
            end

            describe 'attribute access pattern' do
              describe 'getter methods' do
                it 'provides read access to filter' do
                  expect(context.filter).to eq(filter)
                end

                it 'provides read access to patch' do
                  expect(context.patch).to eq(patch)
                end
              end

              describe 'standard setter methods (without underscore)' do
                it 'does not expose filter= setter' do
                  expect(context).not_to respond_to(:filter=)
                end

                it 'does not expose patch= setter' do
                  expect(context).not_to respond_to(:patch=)
                end

                it 'raises NoMethodError when attempting to use filter=' do
                  new_filter = instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter)
                  expect { context.filter = new_filter }.to raise_error(NoMethodError, /filter=/)
                end

                it 'raises NoMethodError when attempting to use patch=' do
                  expect { context.patch = { 'updated' => 'value' } }.to raise_error(NoMethodError, /patch=/)
                end
              end

              describe 'underscore-prefixed setter methods (advanced use)' do
                it 'exposes _filter= for cautious modification' do
                  expect(context).to respond_to(:_filter=)
                end

                it 'exposes _patch= for cautious modification' do
                  expect(context).to respond_to(:_patch=)
                end

                it 'allows modifying filter with _filter=' do
                  new_filter = instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter)
                  context._filter = new_filter
                  expect(context.filter).to eq(new_filter)
                end

                it 'allows modifying patch with _patch=' do
                  new_patch = { 'modified' => 'data' }
                  context._patch = new_patch
                  expect(context.patch).to eq(new_patch)
                end

                it 'signals advanced/cautious use through naming convention' do
                  # The underscore prefix is a Ruby convention indicating:
                  # "This is not the typical way to use this API - proceed with caution"
                  expect(context.methods.grep(/_filter=|_patch=/).size).to eq(2)
                  expect(context.methods.grep(/^filter=$|^patch=$/).size).to eq(0)
                end
              end
            end

            describe 'use case: modifying context in hooks' do
              it 'allows users to intercept and modify the filter' do
                # Simulating a user hook that wants to add additional filtering
                original_filter = context.filter
                modified_filter = instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter)

                # User must use underscore prefix, signaling they know this is advanced
                context._filter = modified_filter

                expect(context.filter).to eq(modified_filter)
                expect(context.filter).not_to eq(original_filter)
              end

              it 'allows users to intercept and modify the patch data' do
                # Simulating a user hook that wants to transform update data
                expect(context.patch['name']).to eq('New Name')

                # User modifies the patch
                modified_patch = context.patch.merge('audit_timestamp' => Time.now)
                context._patch = modified_patch

                expect(context.patch).to have_key('audit_timestamp')
                expect(context.patch['name']).to eq('New Name')
              end
            end
          end
        end
      end
    end
  end
end
