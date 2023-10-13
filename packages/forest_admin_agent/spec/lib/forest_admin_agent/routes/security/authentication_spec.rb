require 'spec_helper'
require 'singleton'

module ForestAdminAgent
  module Routes
    module Security
      describe Authentication do
        subject(:authentication) { described_class.new }

        context 'when setup the routes' do
          it 'adds the route forest_authentication' do
            authentication.setup_routes
            expect(authentication.routes.include?('forest_authentication')).to be true
            expect(authentication.routes.include?('forest_authentication-callback')).to be true
            expect(authentication.routes.include?('forest_logout')).to be true
            expect(authentication.routes.length).to eq 3
          end
        end

        context 'when handle the authentication' do
          let(:rendering_id) { '10' }
          let(:user) do
            {
              'id' => '1',
              'email' => 'john.doe@example.com',
              'first_name' => 'John',
              'last_name' => 'Doe',
              'team' => 'Operations',
              'tags' => [
                {
                  'key' => 'demo',
                  'value' => '1234'
                }
              ],
              'rendering_id' => rendering_id,
              'exp' => (DateTime.now + (1 / 24.0)).to_time.to_i,
              'permission_level' => 'admin'
            }
          end
          let(:token) { JWT.encode :user, ForestAdminAgent::Facades::Container.cache(:auth_secret), 'HS256' }
          let(:auth_manager) { instance_double(ForestAdminAgent::Auth::AuthManager) }

          before do
            allow(ForestAdminAgent::Auth::AuthManager).to receive(:new).and_return(auth_manager)
            allow(auth_manager).to receive(:start).with(any_args).and_return('https://api.development.forestadmin.com/oidc/...')
            allow(auth_manager).to receive(:verify_code_and_generate_token).with(any_args).and_return(token)
          end

          it 'returns an auth url on the handle_authentication method' do
            args = { params: { 'renderingId' => rendering_id } }
            result = authentication.handle_authentication args
            expect(result[:content][:authorizationUrl]).to eq 'https://api.development.forestadmin.com/oidc/...'
          end

          it 'raises an error if renderingId is not present' do
            args = { params: {} }
            expect do
              authentication.handle_authentication args
            end.to raise_error(Error,
                               ForestAdminAgent::Utils::ErrorMessages::MISSING_RENDERING_ID)
          end

          it 'raises an error if renderingId is not an integer' do
            args = { params: { 'renderingId' => 'abc' } }
            expect do
              authentication.handle_authentication args
            end.to raise_error(Error,
                               ForestAdminAgent::Utils::ErrorMessages::INVALID_RENDERING_ID)
          end

          it 'returns a token on the handle_authentication_callback method' do
            result = authentication.handle_authentication_callback 'code' => 'abc',
                                                                   'state' => "{'renderingId': #{rendering_id}}"
            expect(result[:content][:token]).to eq token
            expect(result[:content][:tokenData]).to eq JWT.decode(
              token,
              Facades::Container.cache(:auth_secret),
              true,
              { algorithm: 'HS256' }
            )[0]
          end
        end

        context 'when handle the logout route' do
          it 'returns a 204 status code' do
            result = authentication.handle_authentication_logout
            expect(result[:status]).to eq 204
          end
        end

        it 'when handle auth it should return an AuthManager instance' do
          expect(authentication.auth).to be_an_instance_of(ForestAdminAgent::Auth::AuthManager)
        end
      end
    end
  end
end
