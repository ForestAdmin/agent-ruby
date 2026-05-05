require 'simplecov'
require 'simplecov_json_formatter'
require 'simplecov-html'
require 'forest_admin_datasource_toolkit'
require 'forest_admin_datasource_snowflake'

SimpleCov.formatters = [SimpleCov::Formatter::JSONFormatter, SimpleCov::Formatter::HTMLFormatter]
SimpleCov.start do
  add_filter 'spec'
end

SimpleCov.coverage_dir 'coverage'
SimpleCov.at_exit do
  result = SimpleCov.result
  result.format!
end

Filter              = ForestAdminDatasourceToolkit::Components::Query::Filter
Page                = ForestAdminDatasourceToolkit::Components::Query::Page
Projection          = ForestAdminDatasourceToolkit::Components::Query::Projection
Aggregation         = ForestAdminDatasourceToolkit::Components::Query::Aggregation
Operators           = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
ConditionTreeLeaf   = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
ConditionTreeBranch = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.warnings = false
  config.order = :random
  Kernel.srand config.seed
end
