require_relative 'forest_admin_agent/version'
require_relative 'forest_admin_agent/http/Exceptions/business_error'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect('oauth2' => 'OAuth2')
loader.inflector.inflect('sql' => 'Sql')
loader.inflector.inflect('sse_cache_invalidation' => 'SSECacheInvalidation')
# Rails eager loads every gem loader (Zeitwerk::Loader.eager_load_all): kept autoloaded so ActiveRecord is only
# required once an audit-trail database is configured.
loader.do_not_eager_load("#{__dir__}/forest_admin_agent/audit_trail/sql")
loader.setup

module ForestAdminAgent
  class Error < StandardError; end
  # Your code goes here...
end
