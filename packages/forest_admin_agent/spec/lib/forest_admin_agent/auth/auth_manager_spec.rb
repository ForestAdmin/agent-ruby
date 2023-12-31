require 'spec_helper'
require 'singleton'

module ForestAdminAgent
  module Auth
    describe AuthManager do
      subject(:auth_manager) { described_class.new }

      let(:oidc) { instance_double(ForestAdminAgent::Auth::OidcClientManager) }
      let(:forest_provider) { instance_double(ForestAdminAgent::Auth::OAuth2::ForestProvider) }
      let(:forest_resource_owner) { instance_double(ForestAdminAgent::Auth::OAuth2::ForestResourceOwner) }
      let(:access_token) { instance_double(OpenIDConnect::AccessToken) }

      before do
        allow(ForestAdminAgent::Auth::OidcClientManager).to receive(:new).and_return(oidc)
        allow(oidc).to receive(:make_forest_provider).with(any_args).and_return(forest_provider)
        allow(forest_provider).to receive(:authorization_uri).with(any_args).and_return('https://api.development.forestadmin.com/oidc/...')
        allow(forest_provider).to receive(:authorization_code=).with(any_args).and_return(nil)
        allow(forest_provider).to receive(:access_token!).with(any_args).and_return(access_token)
        allow(forest_provider).to receive(:get_resource_owner).with(access_token).and_return(forest_resource_owner)
        allow(forest_resource_owner).to receive(:make_jwt).and_return('jwt')
      end

      context 'when testing the AuthManager class' do
        it 'returns an auth url on the start method' do
          result = auth_manager.start 10
          expect(result).to eq 'https://api.development.forestadmin.com/oidc/...'
        end

        it 'returns a token on the verify_code_and_generate_token method' do
          result = auth_manager.verify_code_and_generate_token 'code' => 'abc',
                                                               'state' => "{'renderingId': 10}"
          expect(result).to eq 'jwt'
        end

        it 'raises an error when the state is missing' do
          expect do
            auth_manager.verify_code_and_generate_token 'code' => 'abc'
          end.to raise_error(ForestAdminAgent::Utils::ErrorMessages::INVALID_STATE_MISSING)
        end

        it 'raises an error when the rendering state is missing' do
          expect do
            auth_manager.verify_code_and_generate_token 'code' => 'abc',
                                                        'state' => "{'key': 'value'}"
          end.to raise_error(ForestAdminAgent::Utils::ErrorMessages::INVALID_STATE_RENDERING_ID)
        end

        it 'raises an error when the renderingId is not valid' do
          expect do
            auth_manager.verify_code_and_generate_token 'code' => 'abc',
                                                        'state' => "{'renderingId': 'abc'}"
          end.to raise_error(ForestAdminAgent::Utils::ErrorMessages::INVALID_RENDERING_ID)
        end
      end
    end
  end
end
