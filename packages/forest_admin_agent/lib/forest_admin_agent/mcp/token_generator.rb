require 'jwt'
require 'json'

module ForestAdminAgent
  module Mcp
    class TokenGenerator
      def initialize(http_client, auth_secret)
        @http_client = http_client
        @auth_secret = auth_secret
      end

      def generate(client, token_payload)
        response = @http_client.post('/oauth/token', token_payload.to_json)

        unless response.success?
          error_body = parse_error_body(response)
          error_msg = error_body['error_description'] || error_body['error'] || 'Failed to exchange token'
          raise OAuthProvider::InvalidRequestError, error_msg
        end

        result = JSON.parse(response.body)
        build_tokens(client, result)
      end

      private

      def parse_error_body(response)
        JSON.parse(response.body)
      rescue StandardError
        {}
      end

      def build_tokens(client, result)
        forest_access_token = result['access_token']
        forest_refresh_token = result['refresh_token']

        forest_access_decoded = JWT.decode(forest_access_token, nil, false).first
        forest_refresh_decoded = JWT.decode(forest_refresh_token, nil, false).first

        rendering_id = forest_access_decoded.dig('meta', 'renderingId')
        user = fetch_user_info(rendering_id, forest_access_token)

        {
          access_token: build_access_token(user, forest_access_token, forest_access_decoded),
          token_type: 'Bearer',
          expires_in: calculate_expires_in(forest_access_decoded['exp']),
          refresh_token: build_refresh_token(client, user, rendering_id, forest_refresh_token, forest_refresh_decoded),
          scope: forest_access_decoded['scope'] || client['scope']
        }
      end

      def build_access_token(user, forest_access_token, decoded)
        payload = user.merge(server_token: forest_access_token, exp: decoded['exp'])
        JWT.encode(payload, @auth_secret, 'HS256')
      end

      def build_refresh_token(client, user, rendering_id, forest_refresh_token, decoded)
        payload = {
          type: 'refresh',
          client_id: client['client_id'],
          user_id: user[:id],
          rendering_id: rendering_id,
          server_refresh_token: forest_refresh_token,
          exp: decoded['exp']
        }
        JWT.encode(payload, @auth_secret, 'HS256')
      end

      def calculate_expires_in(expiration_date)
        expires_in = expiration_date - Time.now.to_i
        expires_in.positive? ? expires_in : 3600
      end

      def fetch_user_info(rendering_id, access_token)
        response = @http_client.get(
          "/liana/v2/renderings/#{rendering_id}/authorization",
          nil,
          { 'forest-token' => access_token }
        )

        raise OAuthProvider::InvalidRequestError, 'Failed to fetch user info' unless response.success?

        data = JSON.parse(response.body)
        attrs = data.dig('data', 'attributes') || {}

        {
          id: data.dig('data', 'id')&.to_i,
          email: attrs['email'],
          first_name: attrs['first_name'],
          last_name: attrs['last_name'],
          team: attrs['teams']&.first,
          tags: attrs['tags'],
          rendering_id: rendering_id,
          permission_level: attrs['permission_level']
        }
      end
    end
  end
end
