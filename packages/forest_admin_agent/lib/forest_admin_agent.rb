require_relative 'forest_admin_agent/version'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect('oauth2' => 'OAuth2')
loader.inflector.inflect('sse_cache_invalidation' => 'SSECacheInvalidation')
loader.setup

# Eager load business_error.rb which contains all error classes
# This ensures all error classes are available immediately
require_relative 'forest_admin_agent/http/Exceptions/business_error'

module ForestAdminAgent
  class Error < StandardError; end
  # Your code goes here...
end
