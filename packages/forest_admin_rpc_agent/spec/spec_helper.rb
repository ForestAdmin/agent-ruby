require 'simplecov'
require 'simplecov_json_formatter'
require 'simplecov-html'
require 'forest_admin_rpc_agent'
require 'forest_admin_datasource_customizer'
require 'forest_admin_test_toolkit'
require 'singleton'

SimpleCov.formatters = [SimpleCov::Formatter::JSONFormatter, SimpleCov::Formatter::HTMLFormatter]
SimpleCov.start do
  add_filter 'spec'
end

SimpleCov.coverage_dir 'coverage'
SimpleCov.at_exit do
  result = SimpleCov.result
  result.format!
end

RSpec.shared_context 'with caller' do
  let(:caller) { build_caller }
end

RSpec.configure do |config|
  config.include ForestAdminTestToolkit::Factory::Caller
end
