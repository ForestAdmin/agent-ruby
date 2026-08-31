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
require 'forest_admin_datasource_customizer'
require 'forest_admin_datasource_intercom'

# Every payload the specs feed in is hand-written from the Intercom OpenAPI 2.16
# spec, never captured from a workspace: a conversation body is personal data,
# and a fixture is read by everyone who clones the repo.
WebMock.disable_net_connect!(allow_localhost: true)

# A datasource introspects the ticket-type attributes while it registers its
# collections, so every spec building one issues that read. The base url is not
# taken from the datasource on purpose: reading it would build the datasource,
# and boot the very read this stubs.
module IntercomBootStubs
  def stub_ticket_types(*types, base: ForestAdminDatasourceIntercom::Configuration::REGION_HOSTS[:us])
    stub_request(:get, "#{base}/ticket_types")
      .to_return(status: 200, body: { 'type' => 'list', 'data' => types }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end
end

RSpec.configure do |config|
  config.include IntercomBootStubs
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

  config.before do
    WebMock.reset!
    stub_ticket_types
  end
end
