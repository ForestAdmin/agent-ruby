require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      module Context
        include ForestAdminDatasourceToolkit
        include ForestAdminDatasourceToolkit::Decorators

        describe HookContext do
          let(:hook_context) do
            described_class.new(build_collection, caller)
          end

          describe 'raise_error' do
            it 'raise an UnprocessableError' do
              expect do
                hook_context.raise_error('message exception')
              end.to raise_error(ForestAdminDatasourceToolkit::Exceptions::UnprocessableError, 'message exception')
            end
          end

          describe 'raise_forbidden_error' do
            it 'raise an ForbiddenError' do
              expect do
                hook_context.raise_forbidden_error('message exception')
              end.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForbiddenError, 'message exception')
            end
          end

          describe 'raise_validation_error' do
            it 'raise an ValidationError' do
              expect do
                hook_context.raise_validation_error('message exception')
              end.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ValidationError, 'message exception')
            end
          end
        end
      end
    end
  end
end
