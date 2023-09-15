module ForestAdminAgent
  module Utils
    class ErrorMessages
      AUTH_SECRET_MISSING = 'Your Forest authSecret seems to be missing. Can you check that you properly set a Forest
authSecret in the Forest initializer?'.freeze

      SECRET_AND_RENDERINGID_INCONSISTENT = 'Cannot retrieve the project you\'re trying to unlock. The envSecret and
renderingId seems to be missing or inconsistent.'.freeze

      SERVER_DOWN = 'Cannot retrieve the data from the Forest server. Forest API seems to be down right now.'.freeze

      SECRET_NOT_FOUND = 'Cannot retrieve the data from the Forest server. Can you check that you properly copied the
Forest envSecret in the Liana initializer?'.freeze

      UNEXPECTED = 'Cannot retrieve the data from the Forest server. An error occured in Forest API'.freeze

      INVALID_STATE_MISSING = 'Invalid response from the authentication server: the state parameter is missing'.freeze

      INVALID_STATE_FORMAT = 'Invalid response from the authentication server: the state parameter is not at the right
format'.freeze

      INVALID_STATE_RENDERING_ID = 'Invalid response from the authentication server: the state does not contain a
renderingId'.freeze

      MISSING_RENDERING_ID = 'Authentication request must contain a renderingId'.freeze

      INVALID_RENDERING_ID = 'The parameter renderingId is not valid'.freeze

      REGISTRATION_FAILED = 'The registration to the authentication API failed, response: '.freeze

      OIDC_CONFIGURATION_RETRIEVAL_FAILED = 'Failed to retrieve the provider\'s configuration.'.freeze

      TWO_FACTOR_AUTHENTICATION_REQUIRED = 'TwoFactorAuthenticationRequiredForbiddenError'.freeze

      AUTHORIZATION_FAILED = 'Error while authorizing the user on Forest Admin'.freeze
    end
  end
end
