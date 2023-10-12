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
    end
  end
end
