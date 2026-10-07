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

# A datasource checks the API version it was served and introspects the
# ticket-type attributes and the contact and company attributes while it
# registers its collections, so every spec building one issues those four
# reads. The base url is not taken from the datasource on purpose: reading it
# would build the datasource, and boot the very reads this stubs.
module IntercomBootStubs
  def stub_me(base: ForestAdminDatasourceIntercom::Configuration::REGION_HOSTS[:us],
              version: ForestAdminDatasourceIntercom::Configuration::DEFAULT_API_VERSION)
    stub_request(:get, "#{base}/me")
      .to_return(status: 200, body: { 'type' => 'admin', 'id' => '1', 'email' => 'ops@example.test' }.to_json,
                 headers: { 'Content-Type' => 'application/json', 'Intercom-Version' => version })
  end

  def stub_ticket_types(*types, base: ForestAdminDatasourceIntercom::Configuration::REGION_HOSTS[:us])
    stub_request(:get, "#{base}/ticket_types")
      .to_return(status: 200, body: { 'type' => 'list', 'data' => types }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def stub_data_attributes(model, *attributes,
                           base: ForestAdminDatasourceIntercom::Configuration::REGION_HOSTS[:us])
    stub_request(:get, "#{base}/data_attributes").with(query: { 'model' => model })
                                                 .to_return(status: 200,
                                                            body: { 'type' => 'list', 'data' => attributes }.to_json,
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
    stub_me
    stub_ticket_types
    stub_data_attributes('contact')
    stub_data_attributes('company')
  end
end
