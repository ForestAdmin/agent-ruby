require 'active_support'
require 'active_support/core_ext/numeric/time'
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
          Time.now.to_i + 1.hour
        end

        def make_jwt
          attributes = @data['attributes']

          user = {
            id: id,
            email: attributes['email'],
            first_name: attributes['first_name'],
            last_name: attributes['last_name'],
            team: attributes['teams'][0],
            role: attributes['role'],
            tags: attributes['tags'],
            rendering_id: @rendering_id.to_s,
            exp: expiration_in_seconds,
            permission_level: attributes['permission_level']
          }

          JWT.encode user,
                     Facades::Container.cache(:auth_secret),
                     'HS256'
        end
      end
    end
  end
end
