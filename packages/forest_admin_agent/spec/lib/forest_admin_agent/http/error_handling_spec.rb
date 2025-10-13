require 'spec_helper'

module ForestAdminAgent
  module Http
    describe ErrorHandling do
      let(:test_class) do
        Class.new do
          include ForestAdminAgent::Http::ErrorHandling
        end
      end

      subject(:handler) { test_class.new }

      describe '#get_error_message' do
        context 'when error is an HttpException' do
          let(:http_exception) do
            ForestAdminAgent::Http::Exceptions::HttpException.new(500, 'Custom HTTP error message')
          end

          it 'returns the error message from the HttpException' do
            expect(handler.get_error_message(http_exception)).to eq('Custom HTTP error message')
          end
        end

        context 'when error is not an HttpException and no customizer is set' do
          let(:standard_error) { StandardError.new('Standard error message') }

          before do
            allow(ForestAdminAgent::Facades::Container).to receive(:cache).with(:customize_error_message).and_return(nil)
          end

          it 'returns "Unexpected error"' do
            expect(handler.get_error_message(standard_error)).to eq('Unexpected error')
          end
        end

        context 'when error is not an HttpException but customizer is set' do
          let(:custom_error) { RuntimeError.new('Runtime error') }
          let(:customizer) { 'Proc.new { |error| "Custom: #{error.message}" }' }

          before do
            allow(ForestAdminAgent::Facades::Container).to receive(:cache).with(:customize_error_message).and_return(customizer)
          end

          it 'returns the custom error message' do
            expect(handler.get_error_message(custom_error)).to eq('Custom: Runtime error')
          end
        end

        context 'when customizer returns nil' do
          let(:custom_error) { RuntimeError.new('Runtime error') }
          let(:customizer) { 'Proc.new { |error| nil }' }

          before do
            allow(ForestAdminAgent::Facades::Container).to receive(:cache).with(:customize_error_message).and_return(customizer)
          end

          it 'returns "Unexpected error"' do
            expect(handler.get_error_message(custom_error)).to eq('Unexpected error')
          end
        end

        context 'when customizer returns false' do
          let(:custom_error) { RuntimeError.new('Runtime error') }
          let(:customizer) { 'Proc.new { |error| false }' }

          before do
            allow(ForestAdminAgent::Facades::Container).to receive(:cache).with(:customize_error_message).and_return(customizer)
          end

          it 'returns "Unexpected error"' do
            expect(handler.get_error_message(custom_error)).to eq('Unexpected error')
          end
        end

        context 'when error class does not respond to ancestors' do
          let(:weird_error) do
            error = StandardError.new('Weird error')
            allow(error.class).to receive(:respond_to?).with(:ancestors).and_return(false)
            error
          end

          before do
            allow(ForestAdminAgent::Facades::Container).to receive(:cache).with(:customize_error_message).and_return(nil)
          end

          it 'returns "Unexpected error"' do
            expect(handler.get_error_message(weird_error)).to eq('Unexpected error')
          end
        end
      end
    end
  end
end
