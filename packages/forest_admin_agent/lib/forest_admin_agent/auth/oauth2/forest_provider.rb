require 'openid_connect'
require_relative 'forest_resource_owner'

module ForestAdminAgent
  module Auth
    module OAuth2
      class ForestProvider < OpenIDConnect::Client
        attr_reader :rendering_id

        def initialize(rendering_id, attributes = {})
          super(attributes)
          @rendering_id = rendering_id
          @authorization_endpoint = '/oidc/auth'
          @token_endpoint = '/oidc/token'
          self.userinfo_endpoint = "/liana/v2/renderings/#{rendering_id}/authorization"
        end

        def get_resource_owner(access_token)
          headers = { 'forest-token': access_token.access_token, 'forest-secret-key': secret }
          hash = check_response do
            OpenIDConnect.http_client.get access_token.client.userinfo_uri, {}, headers
          end

          response = OpenIDConnect::ResponseObject::UserInfo.new hash

          create_resource_owner response.raw_attributes[:data]
        end

        private

        def create_resource_owner(data)
          ForestResourceOwner.new data, rendering_id
        end

        def check_response
          response = yield
          case response.status
          when 200
            server_error = response.body.key?('errors') ? response.body['errors'][0] : nil
            if server_error &&
               server_error['name'] == Utils::ErrorMessages::TWO_FACTOR_AUTHENTICATION_REQUIRED
              raise Error, Utils::ErrorMessages::TWO_FACTOR_AUTHENTICATION_REQUIRED
            end

            response.body.with_indifferent_access
          when 400
            raise OpenIDConnect::BadRequest.new('API Access Failed', response)
          when 401
            raise OpenIDConnect::Unauthorized.new(Utils::ErrorMessages::AUTHORIZATION_FAILED, response)
          when 403
            error = response.body['errors'].first
            raise OpenIDConnect::Forbidden.new(error['name'], error['detail'])
          when 404
            raise OpenIDConnect::HttpError.new(response.status, Utils::ErrorMessages::SECRET_NOT_FOUND, response)
          when 422
            raise OpenIDConnect::HttpError.new(response.status,
                                               Utils::ErrorMessages::SECRET_AND_RENDERINGID_INCONSISTENT, response)
          else
            raise OpenIDConnect::HttpError.new(response.status, 'Unknown HttpError', response)
          end
        end
      end
    end
  end
end
