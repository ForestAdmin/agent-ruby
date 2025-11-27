require_relative 'forest_admin_datasource_customizer/version'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect('dsl' => 'DSL')
# Collapse subdirectories to avoid creating nested modules
loader.collapse("#{__dir__}/forest_admin_datasource_customizer/dsl/builders")
loader.collapse("#{__dir__}/forest_admin_datasource_customizer/dsl/helpers")
loader.collapse("#{__dir__}/forest_admin_datasource_customizer/dsl/context")
loader.setup

module ForestAdminDatasourceCustomizer
  class Error < StandardError; end
  # Your code goes here...
end
