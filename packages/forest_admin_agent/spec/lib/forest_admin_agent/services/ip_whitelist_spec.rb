require 'spec_helper'
require 'faraday'

module ForestAdminAgent
  module Services
    include ForestAdminDatasourceToolkit

    describe IpWhitelist do
      subject(:ip_whitelist) { described_class.new }

      let(:forest_api_requester) { instance_double(ForestAdminAgent::Http::ForestAdminApiRequester) }

      context 'when there is no rule' do
        before do
          allow(forest_api_requester).to receive(:get).with('/liana/v1/ip-whitelist-rules').and_return(
            instance_double(Faraday::Response,
                            status: 200,
                            body: {
                              'data' => {
                                'type' => 'ip-whitelist-rules',
                                'id' => '1',
                                'attributes' => {
                                  'rules' => [],
                                  'use_ip_whitelist' => false
                                }
                              }
                            }.to_json)
          )

          allow(ip_whitelist).to receive(:forest_api).and_return(forest_api_requester)
        end

        it 'is not enabled' do
          expect(ip_whitelist.enabled?).to be false
        end

        it 'returns empty rules' do
          expect(ip_whitelist.rules).to eq []
        end

        it 'returns false on use_ip_whitelist' do
          expect(ip_whitelist.use_ip_whitelist).to be false
        end
      end

      context 'when server returns 502 status' do
        before do
          allow(forest_api_requester).to receive(:get).with('/liana/v1/ip-whitelist-rules').and_return(
            instance_double(Faraday::Response, status: 502, body: { 'response' => 'Bad Gateway' }.to_json)
          )

          allow(ip_whitelist).to receive(:forest_api).and_return(forest_api_requester)
        end

        it 'raises an error without parsing JSON' do
          expect do
            ip_whitelist.enabled?
          end.to raise_error(Error, ForestAdminAgent::Utils::ErrorMessages::UNEXPECTED)
        end
      end

      context 'when server returns 500 status' do
        before do
          allow(forest_api_requester).to receive(:get).with('/liana/v1/ip-whitelist-rules').and_return(
            instance_double(Faraday::Response, status: 500, body: { 'error' => 'Internal Server Error' }.to_json)
          )

          allow(ip_whitelist).to receive(:forest_api).and_return(forest_api_requester)
        end

        it 'raises an error without parsing JSON' do
          expect do
            ip_whitelist.enabled?
          end.to raise_error(Error, ForestAdminAgent::Utils::ErrorMessages::UNEXPECTED)
        end
      end

      context 'when server returns 404 status' do
        before do
          allow(forest_api_requester).to receive(:get).with('/liana/v1/ip-whitelist-rules').and_return(
            instance_double(Faraday::Response, status: 404, body: { 'error' => 'Not Found' }.to_json)
          )

          allow(ip_whitelist).to receive(:forest_api).and_return(forest_api_requester)
        end

        it 'raises an error without parsing JSON' do
          expect do
            ip_whitelist.enabled?
          end.to raise_error(Error, ForestAdminAgent::Utils::ErrorMessages::UNEXPECTED)
        end
      end

      context 'when API returns invalid JSON' do
        before do
          allow(forest_api_requester).to receive(:get).with('/liana/v1/ip-whitelist-rules').and_return(
            instance_double(Faraday::Response,
                            status: 200,
                            body: 'not valid json {{{')
          )

          allow(ip_whitelist).to receive(:forest_api).and_return(forest_api_requester)
        end

        it 'raises an error' do
          expect do
            ip_whitelist.enabled?
          end.to raise_error(Error, ForestAdminAgent::Utils::ErrorMessages::UNEXPECTED)
        end
      end

      context 'when API returns empty response' do
        before do
          allow(forest_api_requester).to receive(:get).with('/liana/v1/ip-whitelist-rules').and_return(
            instance_double(Faraday::Response,
                            status: 200,
                            body: '')
          )

          allow(ip_whitelist).to receive(:forest_api).and_return(forest_api_requester)
        end

        it 'raises an error' do
          expect do
            ip_whitelist.enabled?
          end.to raise_error(Error, ForestAdminAgent::Utils::ErrorMessages::UNEXPECTED)
        end
      end

      context 'when there is a rule and use_ip_whitelist is true' do
        before do
          allow(forest_api_requester).to receive(:get).with('/liana/v1/ip-whitelist-rules').and_return(
            instance_double(Faraday::Response,
                            status: 200,
                            body: {
                              'data' => {
                                'type' => 'ip-whitelist-rules',
                                'id' => '1',
                                'attributes' => {
                                  'rules' => [
                                    { 'type' => 0, 'ip' => '127.0.0.1' }
                                  ],
                                  'use_ip_whitelist' => true
                                }
                              }
                            }.to_json)
          )

          allow(ip_whitelist).to receive(:forest_api).and_return(forest_api_requester)
        end

        it 'is enabled' do
          expect(ip_whitelist.enabled?).to be true
        end
      end

      context 'when there is a rule of type RULE_MATCH_IP and use_ip_whitelist is true' do
        let(:client_ip) { '127.0.0.1' }
        let(:client2_ip) { '10.10.10.1' }

        before do
          allow(forest_api_requester).to receive(:get).with('/liana/v1/ip-whitelist-rules').and_return(
            instance_double(Faraday::Response,
                            status: 200,
                            body: {
                              'data' => {
                                'type' => 'ip-whitelist-rules',
                                'id' => '1',
                                'attributes' => {
                                  'rules' => [
                                    { 'type' =>  0, 'ip' => '127.0.0.1' }
                                  ],
                                  'use_ip_whitelist' => true
                                }
                              }
                            }.to_json)
          )

          allow(ip_whitelist).to receive(:forest_api).and_return(forest_api_requester)
        end

        it 'returns true when the client ip is in the whitelist' do
          expect(ip_whitelist.ip_matches_any_rule?(client_ip)).to be true
        end

        it 'returns false when the client ip is not in the whitelist' do
          expect(ip_whitelist.ip_matches_any_rule?(client2_ip)).to be false
        end
      end

      context 'when there is a rule of type RULE_MATCH_RANGE and use_ip_whitelist is true' do
        let(:client_ip) { '10.0.0.44' }
        let(:client2_ip) { '10.0.0.200' }

        before do
          allow(forest_api_requester).to receive(:get).with('/liana/v1/ip-whitelist-rules').and_return(
            instance_double(Faraday::Response,
                            status: 200,
                            body: {
                              'data' => {
                                'type' => 'ip-whitelist-rules',
                                'id' => '1',
                                'attributes' => {
                                  'rules' => [
                                    { 'type' =>  1, 'ipMinimum' => '10.0.0.1', 'ipMaximum' => '10.0.0.100' }
                                  ],
                                  'use_ip_whitelist' => true
                                }
                              }
                            }.to_json)
          )

          allow(ip_whitelist).to receive(:forest_api).and_return(forest_api_requester)
        end

        it 'returns true when the client ip is in the whitelist' do
          expect(ip_whitelist.ip_matches_any_rule?(client_ip)).to be true
        end

        it 'returns false when the client ip is not in the whitelist' do
          expect(ip_whitelist.ip_matches_any_rule?(client2_ip)).to be false
        end
      end

      context 'when there is a rule of type RULE_MATCH_SUBNET and use_ip_whitelist is true' do
        let(:client_ip) { '200.10.10.20' }
        let(:client2_ip) { '200.10.20.20' }

        before do
          allow(forest_api_requester).to receive(:get).with('/liana/v1/ip-whitelist-rules').and_return(
            instance_double(Faraday::Response,
                            status: 200,
                            body: {
                              'data' => {
                                'type' => 'ip-whitelist-rules',
                                'id' => '1',
                                'attributes' => {
                                  'rules' => [
                                    { 'type' =>  2, 'range' =>  '200.10.10.0/24' }
                                  ],
                                  'use_ip_whitelist' => true
                                }
                              }
                            }.to_json)
          )

          allow(ip_whitelist).to receive(:forest_api).and_return(forest_api_requester)
        end

        it 'returns true when the client ip is in the whitelist' do
          expect(ip_whitelist.ip_matches_any_rule?(client_ip)).to be true
        end

        it 'returns false when the client ip is not in the whitelist' do
          expect(ip_whitelist.ip_matches_any_rule?(client2_ip)).to be false
        end
      end

      context 'when there is an unknown rule type' do
        let(:client_ip) { '200.10.10.20' }

        before do
          allow(forest_api_requester).to receive(:get).with('/liana/v1/ip-whitelist-rules').and_return(
            instance_double(Faraday::Response,
                            status: 200,
                            body: {
                              'data' => {
                                'type' => 'ip-whitelist-rules',
                                'id' => '1',
                                'attributes' => {
                                  'rules' => [
                                    { 'type' =>  4 }
                                  ],
                                  'use_ip_whitelist' => true
                                }
                              }
                            }.to_json)
          )

          allow(ip_whitelist).to receive(:forest_api).and_return(forest_api_requester)
        end

        it 'raises an error' do
          expect do
            ip_whitelist.ip_matches_any_rule?(client_ip)
          end.to raise_error('Invalid rule type')
        end
      end
    end
  end
end
