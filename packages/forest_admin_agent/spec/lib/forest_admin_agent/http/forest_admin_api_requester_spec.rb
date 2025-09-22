require 'spec_helper'

module ForestAdminAgent
  module Http
    describe ForestAdminApiRequester do
      subject(:forest_admin_api_requester) { described_class.new }

      context 'when the forest admin api is called' do
        let(:response) { instance_double(Faraday::Response, status: 200, body: {}) }
        let(:faraday_connection) { instance_double(Faraday::Connection) }
        let(:params) { { 'params' => 'params' } }
        let(:url) { 'url' }

        before do
          allow(Faraday::Connection).to receive(:new).and_return(faraday_connection)
          allow(faraday_connection).to receive_messages(get: response, post: response)
        end

        it 'returns a response on the get method' do
          result = forest_admin_api_requester.get url, params
          expect(result).to be_a response.class
          expect(result.status).to eq 200
          expect(result.body).to eq({})
        end

        it 'returns a response on the post method' do
          result = forest_admin_api_requester.post url, params
          expect(result).to be_a response.class
          expect(result.status).to eq 200
          expect(result.body).to eq({})
        end
      end

      context 'when the handle response method is called' do
        it 'raises an exception when the error is a ForestException' do
          expect do
            forest_admin_api_requester.handle_response_error(ForestAdminDatasourceToolkit::Exceptions::ForestException.new('test'))
          end.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException)
        end

        it 'raises an exception when the error message contains certificate' do
          expect do
            forest_admin_api_requester.handle_response_error(Faraday::ConnectionFailed.new('test', { message: 'certificate' }))
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            '🌳🌳🌳 ForestAdmin server TLS certificate cannot be verified. Please check that your system time is set properly.'
          )
        end

        it 'raises an exception when the error code is 0' do
          expect do
            forest_admin_api_requester.handle_response_error(Faraday::ConnectionFailed.new('test', { status: 0 }))
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            '🌳🌳🌳 Failed to reach ForestAdmin server. Are you online?'
          )
        end

        it 'raises an exception when the error code is 502' do
          expect do
            forest_admin_api_requester.handle_response_error(Faraday::ConnectionFailed.new('test', { status: 502 }))
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            '🌳🌳🌳 Failed to reach ForestAdmin server. Are you online?'
          )
        end

        it 'raises an exception when the error code is 404' do
          expect do
            forest_admin_api_requester.handle_response_error(Faraday::ConnectionFailed.new('test', { status: 404 }))
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            '🌳🌳🌳 ForestAdmin server failed to find the project related to the envSecret you configured. Can you check that you copied it properly in the Forest initialization?'
          )
        end

        it 'raises an exception when the error code is 503' do
          expect do
            forest_admin_api_requester.handle_response_error(Faraday::ConnectionFailed.new('test', { status: 503 }))
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            '🌳🌳🌳 Forest is in maintenance for a few minutes. We are upgrading your experience in the forest. We just need a few more minutes to get it right.'
          )
        end

        it 'raises an exception when the error code is 500' do
          expect do
            forest_admin_api_requester.handle_response_error(Faraday::ConnectionFailed.new('test', { status: 500 }))
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            '🌳🌳🌳 An unexpected error occurred while contacting the ForestAdmin server. Please contact support@forestadmin.com for further investigations.'
          )
        end
      end
    end
  end
end
