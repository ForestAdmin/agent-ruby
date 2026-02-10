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
              'role' => 'role',
              'tags' => ['tag'],
              'permission_level' => 'permission_level'
            }
          }
        end

        context 'when creating a new ForestResourceOwner' do
          it 'initializes the forest resource owner' do
            expect(forest_resource_owner.id).to eq 'id'
            expect(forest_resource_owner.expiration_in_seconds).to eq Time.now.to_i + 1.hour
          end

          it 'makes a jwt' do
            jwt = forest_resource_owner.make_jwt
            decoded_jwt = JWT.decode jwt, Facades::Container.cache(:auth_secret), true, { algorithm: 'HS256' }
            h = {
              'id' => 'id',
              'email' => 'email',
              'first_name' => 'john',
              'last_name' => 'doe',
              'team' => 'team',
              'role' => 'role',
              'tags' => ['tag'],
              'rendering_id' => '10',
              'exp' => forest_resource_owner.expiration_in_seconds.to_s,
              'permission_level' => 'permission_level'
            }

            expect(decoded_jwt[0]).to eq h
          end
        end
      end
    end
  end
end
