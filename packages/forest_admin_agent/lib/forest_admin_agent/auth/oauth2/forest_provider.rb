require 'openid_connect'
require_relative 'forest_resource_owner'

module ForestAdminAgent
  module Auth
    module OAuth2
      class ForestProvider < OpenIDConnect::Client
        attr_reader :rendering_id

        def initialize(rendering_id, attributes = {})
          super attributes
          @rendering_id = rendering_id
          @authorization_endpoint = '/oidc/auth'
          @token_endpoint = '/oidc/token'
          self.userinfo_endpoint = "/liana/v2/renderings/#{rendering_id}/authorization"
        end

        # public function getResourceOwner(AccessToken $token)
        #     {
        #         $response = $this->fetchResourceOwnerDetails($token);
        #
        #         return $this->createResourceOwner($response, $token);
        #     }

        #  protected function fetchResourceOwnerDetails(AccessToken $token)
        #     {
        #         $url = $this->getResourceOwnerDetailsUrl($token);
        #
        #         $request = $this->getAuthenticatedRequest(self::METHOD_GET, $url, $token);
        #
        #         $response = $this->getParsedResponse($request);
        #
        #         if (false === is_array($response)) {
        #             throw new UnexpectedValueException(
        #                 'Invalid response received from Authorization Server. Expected JSON.'
        #             );
        #         }
        #
        #         return $response;
        #     }
      end
    end
  end
end
