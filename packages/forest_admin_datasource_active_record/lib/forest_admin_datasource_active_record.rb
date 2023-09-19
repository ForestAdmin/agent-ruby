require_relative "forest_admin_datasource_active_record/version"
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.setup

module ForestAdminDatasourceActiveRecord
  class Error < StandardError; end
  # Your code goes here...
end
