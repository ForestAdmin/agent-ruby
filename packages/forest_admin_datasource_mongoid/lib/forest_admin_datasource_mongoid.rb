require_relative 'forest_admin_datasource_mongoid/version'
# require 'forest_admin_datasource_toolkit'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/models")
loader.setup

module ForestAdminDatasourceMongoid
  class Error < StandardError; end
  # Your code goes here...
end
