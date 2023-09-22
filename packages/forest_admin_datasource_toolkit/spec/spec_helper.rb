require 'simplecov'
require 'simplecov_json_formatter'
require "forest_admin_datasource_toolkit"

SimpleCov.formatter = SimpleCov::Formatter::JSONFormatter
SimpleCov.start do
  add_filter 'spec'
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
