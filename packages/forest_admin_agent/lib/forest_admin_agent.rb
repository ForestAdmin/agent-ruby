require_relative 'forest_admin_agent/version'
require_relative 'forest_admin_agent/http/Exceptions/business_error'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect('oauth2' => 'OAuth2')
loader.inflector.inflect('sql' => 'Sql')
loader.inflector.inflect('sse_cache_invalidation' => 'SSECacheInvalidation')
# ActiveRecord is only needed by agents configuring an audit-trail database, and Rails eager loads
# every gem loader (Zeitwerk::Loader.eager_load_all), so these files must stay strictly autoloaded.
loader.do_not_eager_load("#{__dir__}/forest_admin_agent/audit_trail/sql")
loader.setup

module ForestAdminAgent
  class Error < StandardError; end
  # Your code goes here...
end
