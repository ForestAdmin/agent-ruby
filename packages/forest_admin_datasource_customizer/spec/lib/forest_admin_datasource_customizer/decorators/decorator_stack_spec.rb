require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    describe DecoratorsStack do
      let(:initial_datasource) { ForestAdminDatasourceToolkit::Datasource.new }
      let(:new_datasource) { ForestAdminDatasourceToolkit::Datasource.new }
      let(:logger) { instance_double(ForestAdminAgent::Services::LoggerService, log: nil) }

      subject(:stack) { described_class.new(initial_datasource) }

      describe '#reload!' do
        context 'when everything goes well' do
          before do
            stack.queue_customization(-> { stack.instance_variable_set(:@test_flag, true) })
            stack.apply_queued_customizations(logger)
            allow(stack).to receive(:apply_queued_customizations).and_call_original
          end

          it 'resets and reapplies the customizations' do
            stack.reload!(new_datasource, logger)

            expect(stack).to have_received(:apply_queued_customizations).twice
            expect(logger).to have_received(:log).with('Debug', 'Reloading customizations')
            expect(stack.instance_variable_get(:@test_flag)).to be(true)
          end
        end

        context 'when an error occurs during re-application' do
          before do
            stack.queue_customization(-> {})
            allow(stack).to receive(:apply_queued_customizations).and_raise(StandardError.new('fail!'))

            stack.instance_variable_set(:@test_flag, 'original')
          end

          it 'restores the previous state and re-raises the error' do
            expect do
              stack.reload!(new_datasource, logger)
            end.to raise_error(StandardError, 'fail!')

            expect(logger).to have_received(:log).with('Error', /fail!/)
            expect(stack.instance_variable_get(:@test_flag)).to eq('original')
          end
        end
      end
    end
  end
end
