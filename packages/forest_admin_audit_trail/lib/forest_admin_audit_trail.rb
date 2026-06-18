require_relative 'forest_admin_audit_trail/version'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect('sql' => 'Sql')
loader.setup

module ForestAdminAuditTrail
  class Error < StandardError; end
end
