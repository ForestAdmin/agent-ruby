require_relative 'forest_admin_datasource_snowflake/version'
require 'odbc'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect('odbc' => 'ODBC')
loader.setup

module ForestAdminDatasourceSnowflake
  class Error < StandardError; end
end
