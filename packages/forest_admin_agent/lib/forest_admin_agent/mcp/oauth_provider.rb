require 'faraday'
require 'jwt'
require 'json'

module ForestAdminAgent
  module Mcp
    class OAuthProvider
      class InvalidTokenError < StandardError; end
      class InvalidClientError < StandardError; end
      class InvalidRequestError < StandardError; end
      class UnsupportedTokenTypeError < StandardError; end

      attr_reader :environment_id, :environment_api_endpoint

      def initialize(forest_server_url: nil)
        @forest_server_url = forest_server_url || Facades::Container.cache(:forest_server_url)
        @environment_id = nil
        @environment_api_endpoint = nil
      end

      def initialize!
        fetch_environment_id
      end

      def get_client(client_id)
        response = http_client.get("/oauth/register/#{client_id}")

        return nil unless response.success?

        JSON.parse(response.body)
      end

      def authorize_url(client, params)
        frontend_hostname = ENV['FOREST_FRONTEND_HOSTNAME'] || 'https://app.forestadmin.com'

        query_params = {
          redirect_uri: params[:redirect_uri],
          code_challenge: params[:code_challenge],
          code_challenge_method: 'S256',
          response_type: 'code',
          client_id: client['client_id'],
          state: params[:state],
          scope: Array(params[:scopes]).join('+'),
          resource: params[:resource],
          environmentId: @environment_id.to_s
        }

        uri = URI("#{frontend_hostname}/oauth/authorize")
        uri.query = URI.encode_www_form(query_params.compact)
        uri.to_s
      end

      def exchange_authorization_code(client, authorization_code, code_verifier, redirect_uri)
        generate_access_token(client, {
          grant_type: 'authorization_code',
          code: authorization_code,
          redirect_uri: redirect_uri,
          client_id: client['client_id'],
          code_verifier: code_verifier
        })
      end

      def exchange_refresh_token(client, refresh_token, _scopes = nil)
        # Verify and decode the refresh token
        decoded = verify_token(refresh_token)

        # Validate token type
        raise UnsupportedTokenTypeError, 'Invalid token type' unless decoded['type'] == 'refresh'

        # Validate client_id matches
        unless decoded['client_id'] == client['client_id']
          raise InvalidClientError, 'Token was not issued to this client'
        end

        # Exchange the Forest refresh token for new tokens
        generate_access_token(client, {
          grant_type: 'refresh_token',
          refresh_token: decoded['server_refresh_token'],
          client_id: client['client_id']
        })
      end

      def verify_access_token(token)
        decoded = verify_token(token)

        # Ensure this is an access token (not a refresh token)
        if decoded['type'] == 'refresh'
          raise UnsupportedTokenTypeError, 'Cannot use refresh token as access token'
        end

        {
          token: token,
          client_id: decoded['id'].to_s,
          expires_at: decoded['exp'],
          scopes: %w[mcp:read mcp:write mcp:action],
          extra: {
            user_id: decoded['id'],
            email: decoded['email'],
            rendering_id: decoded['rendering_id'],
            environment_api_endpoint: @environment_api_endpoint,
            forest_server_token: decoded['server_token']
          }
        }
      end

      private

      def fetch_environment_id
        env_secret = Facades::Container.cache(:env_secret)
        return unless env_secret

        response = http_client.get('/liana/environment')

        unless response.success?
          ForestAdminAgent::Facades::Container.logger.log(
            'Warn',
            "[MCP] Failed to fetch environmentId from Forest Admin API: #{response.status}"
          )
          return
        end

        data = JSON.parse(response.body)
        @environment_id = data.dig('data', 'id')&.to_i
        @environment_api_endpoint = data.dig('data', 'attributes', 'api_endpoint')
      end

      def generate_access_token(client, token_payload)
        response = http_client.post('/oauth/token', token_payload.to_json)

        unless response.success?
          error_body = JSON.parse(response.body) rescue {}
          error_msg = error_body['error_description'] || error_body['error'] || 'Failed to exchange token'
          raise InvalidRequestError, error_msg
        end

        result = JSON.parse(response.body)
        forest_access_token = result['access_token']
        forest_refresh_token = result['refresh_token']

        # Decode Forest tokens to get metadata
        forest_access_decoded = JWT.decode(forest_access_token, nil, false).first
        forest_refresh_decoded = JWT.decode(forest_refresh_token, nil, false).first

        rendering_id = forest_access_decoded.dig('meta', 'renderingId')
        expiration_date = forest_access_decoded['exp']
        refresh_expiration_date = forest_refresh_decoded['exp']
        scope = forest_access_decoded['scope']

        # Fetch user info from Forest Admin
        user = fetch_user_info(rendering_id, forest_access_token)

        # Calculate expires_in
        now = Time.now.to_i
        expires_in = expiration_date - now
        expires_in = 3600 if expires_in <= 0

        # Create new access token (wrapping the Forest token)
        access_token_payload = user.merge(
          server_token: forest_access_token,
          exp: expiration_date
        )
        access_token = JWT.encode(access_token_payload, auth_secret, 'HS256')

        # Create new refresh token (token rotation for security)
        refresh_token_payload = {
          type: 'refresh',
          client_id: client['client_id'],
          user_id: user[:id],
          rendering_id: rendering_id,
          server_refresh_token: forest_refresh_token,
          exp: refresh_expiration_date
        }
        refresh_token = JWT.encode(refresh_token_payload, auth_secret, 'HS256')

        {
          access_token: access_token,
          token_type: 'Bearer',
          expires_in: expires_in,
          refresh_token: refresh_token,
          scope: scope || client['scope']
        }
      end

      def fetch_user_info(rendering_id, access_token)
        response = http_client.get(
          "/liana/v2/renderings/#{rendering_id}/authorization",
          nil,
          { 'forest-token' => access_token }
        )

        unless response.success?
          raise InvalidRequestError, 'Failed to fetch user info'
        end

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

      def verify_token(token)
        JWT.decode(token, auth_secret, true, { algorithm: 'HS256' }).first
      rescue JWT::ExpiredSignature
        raise InvalidTokenError, 'Token has expired'
      rescue JWT::DecodeError => e
        raise InvalidTokenError, "Invalid token: #{e.message}"
      end

      def auth_secret
        Facades::Container.cache(:auth_secret)
      end

      def http_client
        @http_client ||= Faraday.new(@forest_server_url) do |conn|
          conn.headers['Content-Type'] = 'application/json'
          conn.headers['forest-secret-key'] = Facades::Container.cache(:env_secret)
        end
      end
    end
  end
end
