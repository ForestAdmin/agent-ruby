require_relative "forest_admin_datasource_toolkit/version"
require_relative "forest_admin_datasource_toolkit/exceptions/business_error"
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.setup

module ForestAdminDatasourceToolkit
  class Error < BusinessError; end
  # Your code goes here...
end
