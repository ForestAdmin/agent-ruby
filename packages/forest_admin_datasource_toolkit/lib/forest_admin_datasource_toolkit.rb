require_relative "forest_admin_datasource_toolkit/version"
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/spec")
loader.setup

module ForestAdminDatasourceToolkit
  class Error < StandardError; end
  # Your code goes here...
end
