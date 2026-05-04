require_relative 'forest_admin_datasource_snowflake/version'
require 'odbc'
require 'zeitwerk'

Zeitwerk::Loader.for_gem.setup

module ForestAdminDatasourceSnowflake
  class Error < StandardError; end
end
