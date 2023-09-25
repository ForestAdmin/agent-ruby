require 'spec_helper'
require 'singleton'

module ForestAdminAgent
  module Auth
    module OAuth2
      describe ForestResourceOwner do
        subject(:forest_resource_owner) { described_class.new(data, rendering_id) }

        let(:rendering_id) { 10 }
        let(:data) do
          {
            'id' => 'id',
            'attributes' => {
              'email' => 'email',
              'first_name' => 'john',
              'last_name' => 'doe',
              'teams' => ['team'],
              'tags' => ['tag'],
              'permission_level' => 'permission_level'
            }
          }
        end

        before do
          agent_factory = ForestAdminAgent::Builder::AgentFactory.instance
          agent_factory.setup(
            {
              auth_secret: 'cba803d01a4d43b55010cab41fa1ea1f1f51a95e',
              env_secret: '89719c6d8e2e2de2694c2f220fe2dbf02d5289487364daf1e4c6b13733ed0cdb',
              is_production: false,
              cache_dir: 'tmp/cache/forest_admin',
              debug: true
            }
          )
        end

        context 'when creating a new ForestResourceOwner' do
          it 'initializes the forest resource owner' do
            expect(forest_resource_owner.id).to eq 'id'
            expect(forest_resource_owner.expiration_in_seconds).to eq (DateTime.now + (1 / 24.0)).to_time.to_i
          end

          it 'makes a jwt' do
            jwt = forest_resource_owner.make_jwt
            decoded_jwt = JWT.decode jwt, Facades::Container.get(:auth_secret), true, { algorithm: 'HS256' }
            puts decoded_jwt
            h = {
              'id' => 'id',
              'email' => 'email',
              'first_name' => 'john',
              'last_name' => 'doe',
              'team' => 'team',
              'tags' => ['tag'],
              'rendering_id' => 10,
              'exp' => forest_resource_owner.expiration_in_seconds,
              'permission_level' => 'permission_level'
            }
            expect(decoded_jwt[0]).to eq h
          end
        end
      end
    end
  end
end
