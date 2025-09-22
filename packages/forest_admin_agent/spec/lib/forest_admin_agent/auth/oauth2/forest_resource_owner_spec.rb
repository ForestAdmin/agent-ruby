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

        context 'when creating a new ForestResourceOwner' do
          it 'initializes the forest resource owner' do
            expect(forest_resource_owner.id).to eq 'id'
            expect(forest_resource_owner.expiration_in_seconds).to eq (DateTime.now + (1 / 24.0)).to_time.to_i
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
