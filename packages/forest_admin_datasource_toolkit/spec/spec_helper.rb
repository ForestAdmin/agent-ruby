require 'simplecov'
require 'simplecov_json_formatter'
require 'simplecov-html'
require 'forest_admin_datasource_toolkit'
require 'forest_admin_test_toolkit'
require 'active_support/testing/time_helpers'

SimpleCov.formatters = [SimpleCov::Formatter::JSONFormatter, SimpleCov::Formatter::HTMLFormatter]
SimpleCov.start do
  add_filter 'spec'
end

SimpleCov.coverage_dir 'coverage'
SimpleCov.at_exit do
  result = SimpleCov.result
  result.format!
end

module ConditionTreeSpecHelpers
  def between(field, greater_than, less_than)
    condition_tree = ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    condition_tree::Nodes::ConditionTreeBranch.new('And', [
                                                     condition_tree::Nodes::ConditionTreeLeaf.new(
                                                       field, condition_tree::Operators::GREATER_THAN, greater_than
                                                     ),
                                                     condition_tree::Nodes::ConditionTreeLeaf.new(
                                                       field, condition_tree::Operators::LESS_THAN, less_than
                                                     )
                                                   ]).to_h
  end
end

RSpec.shared_context 'with caller' do
  let(:caller) { build_caller }
end

RSpec.shared_context 'with a frozen clock' do
  let(:paris_thursday_after_midnight) { Time.utc(2026, 5, 13, 22, 30) }

  around { |example| travel_to(paris_thursday_after_midnight) { example.run } }
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include ForestAdminTestToolkit::Factory::Caller
  config.include ForestAdminTestToolkit::Factory::Collection
  config.include ForestAdminTestToolkit::Factory::Datasource
  config.include ActiveSupport::Testing::TimeHelpers
  config.include ConditionTreeSpecHelpers
end
