require_relative 'forest_admin_agent/version'
require 'forest_admin_datasource_toolkit/Exceptions'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect('oauth2' => 'OAuth2')
loader.inflector.inflect('sse_cache_invalidation' => 'SSECacheInvalidation')
loader.setup

module ForestAdminAgent
  class Error < BusinessError; end
  # Your code goes here...
end
