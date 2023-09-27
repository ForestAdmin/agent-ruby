require 'spec_helper'
require 'faraday'

module ForestAdminAgent
  module Auth
    module OAuth2
      include ForestAdminAgent::Utils
      describe ForestProvider do
        let(:rendering_id) { 10 }
        let(:attributes) do
          {
            identifier: 'identifier',
            redirect_uri: 'redirect_uri',
            host: 'host',
            secret: 'secret'
          }
        end
        let(:access_token) { instance_double(OpenIDConnect::AccessToken) }

        subject(:forest_provider) { described_class.new(rendering_id, attributes) }

        context 'when creating a new ForestProvider' do
          it 'initializes the forest provider' do
            expect(forest_provider.rendering_id).to eq rendering_id
            expect(forest_provider.authorization_endpoint).to eq '/oidc/auth'
            expect(forest_provider.token_endpoint).to eq '/oidc/token'
            expect(forest_provider.userinfo_endpoint).to eq "/liana/v2/renderings/#{rendering_id}/authorization"
          end
        end

        context 'when getting the resource owner' do
          before do
            allow(forest_provider).to receive_messages(secret: 'secret')
            allow(forest_provider).to receive_messages(check_response: { data: 'data' })
            allow(access_token).to receive_messages(access_token: 'access_token')
            allow(access_token).to receive_messages(client: forest_provider)
          end

          it 'returns the resource owner' do
            result = forest_provider.get_resource_owner(access_token)
            expect(result).to be_instance_of ForestAdminAgent::Auth::OAuth2::ForestResourceOwner
          end
        end

        context 'when check response is called' do
          before do
            allow(access_token).to receive_messages(access_token: 'access_token')
            allow(access_token).to receive_messages(client: forest_provider)
            allow(Faraday::Connection).to receive(:new).and_return(faraday_connection)
          end

          context 'when a response return 200 status' do
            let(:faraday_connection) { instance_double(Faraday::Connection) }
            let(:response_ok) { instance_double(Faraday::Response, status: 200, body: { 'data' => 'data' }) }
            let(:response_ok_with_error) do
              instance_double(
                Faraday::Response,
                status: 200,
                body: { 'errors' => [{ 'name' => ErrorMessages::TWO_FACTOR_AUTHENTICATION_REQUIRED }] }
              )
            end

            it 'returns the response body' do
              allow(faraday_connection).to receive(:get).and_return(response_ok)
              result = forest_provider.get_resource_owner(access_token)
              expect(result).to be_instance_of ForestAdminAgent::Auth::OAuth2::ForestResourceOwner
            end

            it 'raise an error when the body contains an error' do
              allow(faraday_connection).to receive(:get).and_return(response_ok_with_error)
              expect do
                forest_provider.get_resource_owner(access_token)
              end.to raise_error(ErrorMessages::TWO_FACTOR_AUTHENTICATION_REQUIRED)
            end
          end

          context 'when checking a response not 200 status' do
            let(:faraday_connection) { instance_double(Faraday::Connection) }
            let(:response_bad_request) { instance_double(Faraday::Response, status: 400) }
            let(:response_unauthorized) { instance_double(Faraday::Response, status: 401) }
            let(:response_not_found) { instance_double(Faraday::Response, status: 404) }
            let(:response_unprocessable) { instance_double(Faraday::Response, status: 422) }
            let(:response_internal_error) { instance_double(Faraday::Response, status: 500) }

            it 'raises an error when the response is 400' do
              allow(faraday_connection).to receive(:get).and_return(response_bad_request)
              expect { forest_provider.get_resource_owner(access_token) }.to raise_error(OpenIDConnect::BadRequest)
            end

            it 'raises an error when the response is 401' do
              allow(faraday_connection).to receive(:get).and_return(response_unauthorized)
              expect { forest_provider.get_resource_owner(access_token) }.to raise_error(OpenIDConnect::Unauthorized)
            end

            it 'raises an error when the response is 404' do
              allow(faraday_connection).to receive(:get).and_return(response_not_found)
              expect { forest_provider.get_resource_owner(access_token) }.to raise_error(OpenIDConnect::HttpError)
            end

            it 'raises an error when the response is 422' do
              allow(faraday_connection).to receive(:get).and_return(response_unprocessable)
              expect { forest_provider.get_resource_owner(access_token) }.to raise_error(OpenIDConnect::HttpError)
            end

            it 'raises an error when the response is 500' do
              allow(faraday_connection).to receive(:get).and_return(response_internal_error)
              expect { forest_provider.get_resource_owner(access_token) }.to raise_error(OpenIDConnect::HttpError)
            end
          end
        end
      end
    end
  end
end
