require_relative 'forest_admin_datasource_customizer/version'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.setup

module ForestAdminDatasourceCustomizer
  extend T::Sig

  class Error < StandardError; end
  # Your code goes here...
end
