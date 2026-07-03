require 'simplecov'
require 'simplecov_json_formatter'
require 'simplecov-html'
require 'active_record'
require 'sqlite3'
require 'forest_admin_datasource_toolkit'
require 'forest_admin_datasource_customizer'
require 'forest_admin_audit_trail'

SimpleCov.formatters = [SimpleCov::Formatter::JSONFormatter, SimpleCov::Formatter::HTMLFormatter]
SimpleCov.start do
  add_filter 'spec'
end

SimpleCov.coverage_dir 'coverage'
SimpleCov.at_exit do
  result = SimpleCov.result
  result.format!
end

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
