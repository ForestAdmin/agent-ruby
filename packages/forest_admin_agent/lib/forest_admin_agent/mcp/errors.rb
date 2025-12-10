module ForestAdminAgent
  module Mcp
    class InvalidTokenError < StandardError; end
    class InvalidClientError < StandardError; end
    class InvalidRequestError < StandardError; end
    class UnsupportedTokenTypeError < StandardError; end
  end
end
