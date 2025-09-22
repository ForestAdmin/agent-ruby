require 'simplecov'
require 'simplecov_json_formatter'
require 'simplecov-html'
require 'forest_admin_rpc_agent'
require 'forest_admin_datasource_customizer'
require 'forest_admin_datasource_rpc'
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
  config.before do
    agent_factory = ForestAdminRpcAgent::Agent.instance
    agent_factory.setup(
      {
        auth_secret: 'cba803d01a4d43b55010cab41fa1ea1f1f51a95e',
        env_secret: '89719c6d8e2e2de2694c2f220fe2dbf02d5289487364daf1e4c6b13733ed0cdb',
        is_production: false,
        cache_dir: 'tmp/cache/forest_admin',
        schema_path: File.join('tmp', '.forestadmin-schema.json'),
        forest_server_url: 'https://api.development.forestadmin.com',
        debug: true,
        prefix: 'forest',
        customize_error_message: nil
      }
    )
  end

  # rspec-expectations config goes here. You can use an alternate
  # assertion/expectation library such as wrong or the stdlib/minitest
  # assertions if you prefer.
  config.expect_with :rspec do |expectations|
    # This option will default to `true` in RSpec 4. It makes the `description`
    # and `failure_message` of custom matchers include text for helper methods
    # defined using `chain`, e.g.:
    #     be_bigger_than(2).and_smaller_than(4).description
    #     # => "be bigger than 2 and smaller than 4"
    # ...rather than:
    #     # => "be bigger than 2"
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # rspec-mocks config goes here. You can use an alternate test double
  # library (such as bogus or mocha) by changing the `mock_with` option here.
  config.mock_with :rspec do |mocks|
    # Prevents you from mocking or stubbing a method that does not exist on
    # a real object. This is generally recommended, and will default to
    # `true` in RSpec 4.
    mocks.verify_partial_doubles = true
  end

  # This option will default to `:apply_to_host_groups` in RSpec 4 (and will
  # have no way to turn it off -- the option exists only for backwards
  # compatibility in RSpec 3). It causes shared context metadata to be
  # inherited by the metadata hash of host groups and examples, rather than
  # triggering implicit auto-inclusion in groups with matching metadata.
  config.shared_context_metadata_behavior = :apply_to_host_groups
end
