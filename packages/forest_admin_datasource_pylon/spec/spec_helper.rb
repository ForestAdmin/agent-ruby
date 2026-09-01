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
require 'forest_admin_datasource_pylon'

WebMock.disable_net_connect!(allow_localhost: true)

# A datasource introspects the custom fields of its three object types while it
# registers its collections. A spec building one declares what those calls
# answer -- most of them, having nothing to do with custom fields, answer
# nothing. The base url is not taken from the datasource on purpose: reading it
# would build the datasource, and boot the introspection this stubs.
module PylonCustomFieldStubs
  def stub_custom_fields(issue: [], account: [], contact: [],
                         base: ForestAdminDatasourcePylon::Configuration::DEFAULT_BASE_URL)
    { 'issue' => issue, 'account' => account, 'contact' => contact }.each do |object_type, definitions|
      stub_request(:get, "#{base}/custom-fields")
        .with(query: { 'object_type' => object_type })
        .to_return(status: 200, body: { 'data' => definitions }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end
  end
end

RSpec.configure do |config|
  config.include PylonCustomFieldStubs

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
