require 'spec_helper'

module ForestAdminAgent
  module Http
    describe ErrorTranslator do
      describe '.translate' do
        context 'when error is an HttpException' do
          let(:http_exception) do
            ForestAdminAgent::Http::Exceptions::HttpException.new(500, 'StandardError', 'Custom HTTP error message')
          end

          it 'returns the HttpException as-is' do
            result = described_class.translate(http_exception)
            expect(result).to eq(http_exception)
            expect(result.message).to eq('Custom HTTP error message')
          end
        end

        context 'when error is not an HttpException and no customizer is set' do
          let(:standard_error) { StandardError.new('Standard error message') }

          before do
            allow(ForestAdminAgent::Facades::Container).to receive(:cache).with(:customize_error_message).and_return(nil)
          end

          it 'returns an HttpException with "Unexpected error" message' do
            result = described_class.translate(standard_error)
            expect(result).to be_a(ForestAdminAgent::Http::Exceptions::HttpException)
            expect(result.message).to eq('Unexpected error')
            expect(result.status).to eq(500)
          end
        end

        context 'when error is not an HttpException but customizer is set' do
          let(:custom_error) { RuntimeError.new('Runtime error') }
          let(:customizer) { 'Proc.new { |error| "Custom: #{error.message}" }' }

          before do
            allow(ForestAdminAgent::Facades::Container).to receive(:cache).with(:customize_error_message).and_return(customizer)
          end

          it 'returns the custom error message' do
            result = described_class.translate(custom_error)
            expect(result.message).to eq('Custom: Runtime error')
          end
        end

        context 'when customizer returns nil' do
          let(:custom_error) { RuntimeError.new('Runtime error') }
          let(:customizer) { 'Proc.new { |error| nil }' }

          before do
            allow(ForestAdminAgent::Facades::Container).to receive(:cache).with(:customize_error_message).and_return(customizer)
          end

          it 'returns "Unexpected error"' do
            result = described_class.translate(custom_error)
            expect(result.message).to eq('Unexpected error')
          end
        end

        context 'when customizer returns false' do
          let(:custom_error) { RuntimeError.new('Runtime error') }
          let(:customizer) { 'Proc.new { |error| false }' }

          before do
            allow(ForestAdminAgent::Facades::Container).to receive(:cache).with(:customize_error_message).and_return(customizer)
          end

          it 'returns "Unexpected error"' do
            result = described_class.translate(custom_error)
            expect(result.message).to eq('Unexpected error')
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
            result = described_class.translate(weird_error)
            expect(result.message).to eq('Unexpected error')
          end
        end

        context 'when error is a ValidationError' do
          let(:validation_error) do
            ForestAdminDatasourceToolkit::Exceptions::ValidationError.new('The query violates a unicity constraint')
          end

          before do
            allow(ForestAdminAgent::Facades::Container).to receive(:cache).with(:customize_error_message).and_return(nil)
          end

          it 'returns the validation error message' do
            result = described_class.translate(validation_error)
            expect(result.message).to eq('The query violates a unicity constraint')
          end
        end

        context 'when error is a BusinessError' do
          let(:business_error) do
            ForestAdminAgent::Http::Exceptions::BadRequestError.new('Bad request error')
          end

          it 'returns the business error message' do
            result = described_class.translate(business_error)
            expect(result.message).to eq('Bad request error')
            expect(result.status).to eq(400)
          end
        end
      end

      describe 'status code mapping' do
        context 'when error is a ValidationError' do
          let(:validation_error) do
            ForestAdminDatasourceToolkit::Exceptions::ValidationError.new('Invalid data')
          end

          it 'returns 400' do
            result = described_class.translate(validation_error)
            expect(result.status).to eq(400)
          end
        end

        context 'when error is a BadRequestError' do
          let(:bad_request_error) do
            ForestAdminAgent::Http::Exceptions::BadRequestError.new('Bad request')
          end

          it 'returns 400' do
            result = described_class.translate(bad_request_error)
            expect(result.status).to eq(400)
          end
        end

        context 'when error is a ForbiddenError' do
          let(:forbidden_error) do
            ForestAdminAgent::Http::Exceptions::ForbiddenError.new('Forbidden')
          end

          it 'returns 403' do
            result = described_class.translate(forbidden_error)
            expect(result.status).to eq(403)
          end
        end

        context 'when error is a NotFoundError' do
          let(:not_found_error) do
            ForestAdminAgent::Http::Exceptions::NotFoundError.new('Not found')
          end

          it 'returns 404' do
            result = described_class.translate(not_found_error)
            expect(result.status).to eq(404)
          end
        end

        context 'when error is an UnprocessableError' do
          let(:unprocessable_error) do
            ForestAdminAgent::Http::Exceptions::UnprocessableError.new('Unprocessable')
          end

          it 'returns 422' do
            result = described_class.translate(unprocessable_error)
            expect(result.status).to eq(422)
          end
        end

        context 'when error does not have a status method' do
          let(:standard_error) { StandardError.new('Standard error message') }

          it 'returns 500' do
            result = described_class.translate(standard_error)
            expect(result.status).to eq(500)
          end
        end
      end
    end
  end
end
