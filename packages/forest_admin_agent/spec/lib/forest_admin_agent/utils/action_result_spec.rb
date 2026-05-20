require 'spec_helper'

module ForestAdminAgent
  module Utils
    describe ActionResult do
      describe '.parse' do
        context 'when the result type is Success' do
          let(:result) do
            {
              type: 'Success',
              message: 'Done',
              invalidated: %w[books authors],
              html: '<p>ok</p>',
              response_headers: { 'x-foo' => 'bar' }
            }
          end

          it 'maps Success keys and forwards response_headers' do
            expect(described_class.parse(result)).to eq(
              success: 'Done',
              refresh: { relationships: %w[books authors] },
              html: '<p>ok</p>',
              headers: { 'x-foo' => 'bar' }
            )
          end
        end

        context 'when the result type is Error' do
          let(:result) { { type: 'Error', message: 'Boom', html: nil } }

          it 'maps Error keys with status 400' do
            expect(described_class.parse(result)).to eq(
              status: 400,
              error: 'Boom',
              html: nil,
              headers: nil
            )
          end
        end

        context 'when the result type is Webhook' do
          let(:result) do
            {
              type: 'Webhook',
              body: { foo: 'bar' },
              headers: { 'x-h' => '1' },
              method: 'POST',
              url: 'https://example.test/hook'
            }
          end

          it 'maps Webhook keys' do
            expect(described_class.parse(result)).to eq(
              webhook: {
                body: { foo: 'bar' },
                headers: { 'x-h' => '1' },
                method: 'POST',
                url: 'https://example.test/hook'
              },
              headers: nil
            )
          end
        end

        context 'when the result type is File' do
          let(:content) { 'binary-payload' }
          let(:result) do
            {
              type: 'File',
              name: 'report.pdf',
              mime_type: 'application/pdf',
              stream: content,
              response_headers: { 'set-cookie' => 'token=xyz' }
            }
          end

          it 'maps File keys including :type so the controller can detect a file response' do
            parsed = described_class.parse(result)

            expect(parsed[:type]).to eq('File')
            expect(parsed[:name]).to eq('report.pdf')
            expect(parsed[:mime_type]).to eq('application/pdf')
            expect(parsed[:stream]).to eq(content)
            expect(parsed[:headers]).to eq({ 'set-cookie' => 'token=xyz' })
          end

          it 'reads the payload from :stream (the key ResultBuilder.file writes)' do
            parsed = described_class.parse(result)
            expect(parsed[:stream]).to eq(content)
          end
        end

        context 'when the result type is Redirect' do
          let(:result) { { type: 'Redirect', path: '/anywhere' } }

          it 'maps Redirect keys' do
            expect(described_class.parse(result)).to eq(
              redirect_to: '/anywhere',
              headers: nil
            )
          end
        end

        context 'when the result type is unknown' do
          let(:result) { { type: 'Mystery' } }

          it 'returns only the merged response_headers' do
            expect(described_class.parse(result)).to eq(headers: nil)
          end
        end
      end
    end
  end
end
