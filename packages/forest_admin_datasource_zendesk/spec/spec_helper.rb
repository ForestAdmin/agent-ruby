require 'simplecov'
# JSON output is consumed by the qlty CI coverage step; HTML is for local
# inspection. simplecov-html and simplecov_json_formatter are required only
# in Gemfile-test, so guard the require for local Gemfile runs.
begin
  require 'simplecov_json_formatter'
  require 'simplecov-html'
  SimpleCov.formatters = [SimpleCov::Formatter::JSONFormatter, SimpleCov::Formatter::HTMLFormatter]
rescue LoadError
  # Local Gemfile run without the CI formatters; default text output is fine.
end

SimpleCov.start do
  add_filter '/spec/'
  enable_coverage :branch
  minimum_coverage 90
end

SimpleCov.coverage_dir 'coverage'

require 'webmock/rspec'
require 'forest_admin_datasource_zendesk'

WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.mock_with :rspec do |m|
    m.verify_partial_doubles = true
  end
  config.disable_monkey_patching!
  config.warnings = false
  config.order = :random
  Kernel.srand config.seed

  config.before { WebMock.reset! }
end
