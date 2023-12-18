require_relative 'forest_admin_datasource_customizer/version'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.setup

module ForestAdminDatasourceCustomizer
  class Error < StandardError; end
  # Your code goes here...
end
