require 'spec_helper'
require 'net/http'

module ForestAdminAgent
  module Services
    describe IpWhitelist do
      subject(:ip_whitelist) { described_class.new }

      let(:net_http) { class_double(Net::HTTP).as_stubbed_const }
      let(:net_http_response) { Net::HTTPSuccess.new('1.1', '200', 'OK') }

      context 'when there is no rule' do
        before do
          allow(net_http_response).to receive(:body).and_return('{
            "data":{
              "type":"ip-whitelist-rules",
              "id":"1",
              "attributes":{
                "rules":[],
                "use_ip_whitelist":false
              }
            }
          }')
          allow(net_http).to receive(:get_response).and_return(net_http_response)
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

      context 'when there is bad response from the server' do
        before do
          allow(net_http).to receive(:get_response).and_return(Net::HTTPBadGateway)
        end

        it 'is not enabled' do
          expect do
            ip_whitelist.enabled?
          end.to raise_error(ForestAdminAgent::Utils::ErrorMessages::UNEXPECTED)
        end
      end

      context 'when there is a rule and use_ip_whitelist is true' do
        before do
          allow(net_http_response).to receive(:body).and_return('{
            "data":{
              "type":"ip-whitelist-rules",
              "id":"1",
              "attributes":{
                "rules":[
                  { "type": 0, "ip": "127.0.0.1" }
                ],
                "use_ip_whitelist":true
              }
            }
          }')
          allow(net_http).to receive(:get_response).and_return(net_http_response)
        end

        it 'is enabled' do
          expect(ip_whitelist.enabled?).to be true
        end
      end

      context 'when there is a rule of type RULE_MATCH_IP and use_ip_whitelist is true' do
        let(:client_ip) { '127.0.0.1' }
        let(:client2_ip) { '10.10.10.1' }

        before do
          allow(net_http_response).to receive(:body).and_return('{
            "data":{
              "type":"ip-whitelist-rules",
              "id":"1",
              "attributes":{
                "rules":[
                  { "type": 0, "ip": "127.0.0.1" }
                ],
                "use_ip_whitelist":true
              }
            }
          }')
          allow(net_http).to receive(:get_response).and_return(net_http_response)
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
          allow(net_http_response).to receive(:body).and_return('{
            "data":{
              "type":"ip-whitelist-rules",
              "id":"1",
              "attributes":{
                "rules":[
                  { "type": 1, "ipMinimum": "10.0.0.1", "ipMaximum": "10.0.0.100"}
                ],
                "use_ip_whitelist":true
              }
            }
          }')
          allow(net_http).to receive(:get_response).and_return(net_http_response)
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
          allow(net_http_response).to receive(:body).and_return('{
            "data":{
              "type":"ip-whitelist-rules",
              "id":"1",
              "attributes":{
                "rules":[
                  { "type": 2, "range": "200.10.10.0/24"}
                ],
                "use_ip_whitelist":true
              }
            }
          }')
          allow(net_http).to receive(:get_response).and_return(net_http_response)
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
          allow(net_http_response).to receive(:body).and_return('{
            "data":{
              "type":"ip-whitelist-rules",
              "id":"1",
              "attributes":{
                "rules":[
                  { "type": 4}
                ],
                "use_ip_whitelist":true
              }
            }
          }')
          allow(net_http).to receive(:get_response).and_return(net_http_response)
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
