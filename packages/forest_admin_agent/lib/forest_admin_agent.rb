require_relative 'forest_admin_agent/version'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect('oauth2' => 'OAuth2')
loader.inflector.inflect('sse_cache_invalidation' => 'SSECacheInvalidation')
loader.setup

module ForestAdminAgent
  extend T::Sig

  class Error < StandardError; end
  # Your code goes here...
end
