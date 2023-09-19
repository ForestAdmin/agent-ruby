require 'date'
require 'jwt'

module ForestAdminAgent
  module Auth
    module OAuth2
      class ForestResourceOwner
        def initialize(data, rendering_id)
          @data = data
          @rendering_id = rendering_id
        end

        def id
          @data['id']
        end

        def expiration_in_seconds
          (DateTime.now + (1 / 24.0)).to_time.to_i
        end

        def make_jwt
          attributes = @data['attributes']
          user = {
            id: id,
            email: attributes['email'],
            first_name: attributes['first_name'],
            last_name: attributes['last_name'],
            team: attributes['teams'][0],
            tags: attributes['tags'],
            rendering_id: @rendering_id,
            exp: expiration_in_seconds,
            permission_level: attributes['permission_level']
          }

          JWT.encode user,
                     Facades::Container.get(:auth_secret),
                     'HS256'
        end
      end
    end
  end
end
