require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Decorators

      describe Hooks do
        let(:fake_hook_context) do
          Class.new(Context::HookContext) do
            attr_accessor :foo

            def initialize
              collection = ForestAdminDatasourceToolkit::Collection.new(
                ForestAdminDatasourceToolkit::Datasource.new,
                'collection'
              )
              super(collection, caller)
            end
          end
        end

        subject(:hooks) { described_class }

        describe 'execute_before' do
          describe 'when multiple before hooks are defined' do
            it 'call all of them' do
              first_hook = instance_double(Proc, call: nil)
              second_hook = instance_double(Proc, call: nil)

              hooks = described_class.new
              hooks.add_handler('before', first_hook)
              hooks.add_handler('before', second_hook)
              hooks.execute_before(fake_hook_context.new)

              expect(first_hook).to have_received(:call).once
              expect(second_hook).to have_received(:call).once
            end

            it 'call the second hook with the update context' do
              first_hook = proc { |context| context.foo = 1 }
              second_hook = instance_double(Proc, call: nil)

              hooks = described_class.new
              hooks.add_handler('before', first_hook)
              hooks.add_handler('before', second_hook)
              hooks.execute_before(fake_hook_context.new)

              expect(second_hook).to have_received(:call) do |context|
                expect(context.foo).to eq(1)
              end
            end

            describe 'when the first hook raise an error' do
              it 'prevent the second hook to run' do
                first_hook = proc { raise 'This is an exception' }
                second_hook = instance_double(Proc, call: nil)

                hooks = described_class.new
                hooks.add_handler('before', first_hook)
                hooks.add_handler('before', second_hook)

                expect { hooks.execute_before(fake_hook_context.new) }.to raise_error(RuntimeError)
                expect(second_hook).not_to have_received(:call)
              end
            end
          end

          describe 'when after hook are defined' do
            it 'call all of them' do
              hook = instance_double(Proc, call: nil)

              hooks = described_class.new
              hooks.add_handler('after', hook)
              hooks.execute_before(fake_hook_context.new)

              expect(hook).not_to have_received(:call)
            end
          end
        end

        describe 'execute_after' do
          describe 'when multiple after hooks are defined' do
            it 'call all of them' do
              first_hook = instance_double(Proc, call: nil)
              second_hook = instance_double(Proc, call: nil)

              hooks = described_class.new
              hooks.add_handler('after', first_hook)
              hooks.add_handler('after', second_hook)
              hooks.execute_after(fake_hook_context.new)

              expect(first_hook).to have_received(:call).once
              expect(second_hook).to have_received(:call).once
            end

            it 'call the second hook with the update context' do
              first_hook = proc { |context| context.foo = 1 }
              second_hook = instance_double(Proc, call: nil)

              hooks = described_class.new
              hooks.add_handler('after', first_hook)
              hooks.add_handler('after', second_hook)
              hooks.execute_after(fake_hook_context.new)

              expect(second_hook).to have_received(:call) do |context|
                expect(context.foo).to eq(1)
              end
            end

            describe 'when the first hook raise an error' do
              it 'prevent the second hook to run' do
                first_hook = proc { raise 'This is an exception' }
                second_hook = instance_double(Proc, call: nil)

                hooks = described_class.new
                hooks.add_handler('after', first_hook)
                hooks.add_handler('after', second_hook)

                expect { hooks.execute_after(fake_hook_context.new) }.to raise_error(RuntimeError)
                expect(second_hook).not_to have_received(:call)
              end
            end
          end

          describe 'when before hook are defined' do
            it 'call all of them' do
              hook = instance_double(Proc, call: nil)

              hooks = described_class.new
              hooks.add_handler('before', hook)
              hooks.execute_after(fake_hook_context.new)

              expect(hook).not_to have_received(:call)
            end
          end
        end
      end
    end
  end
end
