require 'faraday'
require 'jwt'
require 'json'

module ForestAdminAgent
  module Mcp
    class OauthProvider
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
        response.success? ? JSON.parse(response.body) : nil
      end

      def authorize_url(client, params)
        frontend_hostname = ENV.fetch('FOREST_FRONTEND_HOSTNAME', 'https://app.forestadmin.com')
        query_params = build_authorize_params(client, params)
        uri = URI("#{frontend_hostname}/oauth/authorize")
        uri.query = URI.encode_www_form(query_params.compact)
        uri.to_s
      end

      def exchange_authorization_code(client, authorization_code, code_verifier, redirect_uri)
        payload = authorization_code_payload(client, authorization_code, code_verifier, redirect_uri)
        token_generator.generate(client, payload)
      end

      def exchange_refresh_token(client, refresh_token, _scopes = nil)
        decoded = verify_token(refresh_token)
        validate_refresh_token(decoded, client)
        token_generator.generate(client, refresh_token_payload(client, decoded))
      end

      def verify_access_token(token)
        decoded = verify_token(token)
        raise UnsupportedTokenTypeError, 'Cannot use refresh token as access token' if decoded['type'] == 'refresh'

        build_auth_info(token, decoded)
      end

      private

      def authorization_code_payload(client, code, verifier, redirect_uri)
        { grant_type: 'authorization_code', code: code, redirect_uri: redirect_uri,
          client_id: client['client_id'], code_verifier: verifier }
      end

      def refresh_token_payload(client, decoded)
        { grant_type: 'refresh_token', refresh_token: decoded['server_refresh_token'], client_id: client['client_id'] }
      end

      def build_authorize_params(client, params)
        { redirect_uri: params[:redirect_uri], code_challenge: params[:code_challenge],
          code_challenge_method: 'S256', response_type: 'code', client_id: client['client_id'],
          state: params[:state], scope: Array(params[:scopes]).join('+'),
          resource: params[:resource], environmentId: @environment_id.to_s }
      end

      def validate_refresh_token(decoded, client)
        raise UnsupportedTokenTypeError, 'Invalid token type' unless decoded['type'] == 'refresh'
        raise InvalidClientError, 'Token was not issued to this client' if decoded['client_id'] != client['client_id']
      end

      def build_auth_info(token, decoded)
        { token: token, client_id: decoded['id'].to_s, expires_at: decoded['exp'],
          scopes: %w[mcp:read mcp:write mcp:action],
          extra: { user_id: decoded['id'], email: decoded['email'], rendering_id: decoded['rendering_id'],
                   environment_api_endpoint: @environment_api_endpoint, forest_server_token: decoded['server_token'] } }
      end

      def fetch_environment_id
        return unless Facades::Container.cache(:env_secret)

        response = http_client.get('/liana/environment')
        return log_env_error(response.status) unless response.success?

        data = JSON.parse(response.body)
        @environment_id = data.dig('data', 'id')&.to_i
        @environment_api_endpoint = data.dig('data', 'attributes', 'api_endpoint')
      end

      def log_env_error(status)
        Facades::Container.logger.log('Warn', "[MCP] Failed to fetch environmentId: #{status}")
      end

      def verify_token(token)
        JWT.decode(token, auth_secret, true, { algorithm: 'HS256' }).first
      rescue JWT::ExpiredSignature
        raise InvalidTokenError, 'Token has expired'
      rescue JWT::DecodeError => e
        raise InvalidTokenError, "Invalid token: #{e.message}"
      end

      def token_generator
        @token_generator ||= TokenGenerator.new(http_client, auth_secret)
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
