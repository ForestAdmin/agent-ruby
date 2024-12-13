require 'filecache'
require 'simplecov'
require 'simplecov_json_formatter'
require 'simplecov-html'
require 'forest_admin_agent'
require 'forest_admin_datasource_toolkit'
require 'forest_admin_datasource_customizer'
require 'forest_admin_test_toolkit'
require 'singleton'

SimpleCov.formatters = [SimpleCov::Formatter::JSONFormatter, SimpleCov::Formatter::HTMLFormatter]
SimpleCov.start do
  add_filter 'spec'
  add_filter 'lib/forest_admin_agent/auth/oauth2/oidc_config.rb'
  add_filter 'lib/forest_admin_agent/serializer/json_api_serializer.rb'
end

RSpec.shared_context 'with caller' do
  let(:bearer) do
    # TODO: improve with a build token function
    'Bearer eyJhbGciOiJIUzI1NiJ9.eyJpZCI6IjEiLCJlbWFpbCI6Im5pY29sYXNhQGZvcmVzdGFkbWluLmNvbSIsImZpcnN0X25hbWUiOiJOaWNvbGFzIiwibGFzdF9uYW1lIjoiQWxleGFuZHJlIiwidGVhbSI6Ik9wZXJhdGlvbnMiLCJ0YWdzIjpbXSwicmVuZGVyaW5nX2lkIjoxMTQsImV4cCI6MTk5ODAzNjQ0OSwicGVybWlzc2lvbl9sZXZlbCI6ImFkbWluIn0.5LFmtMqZMfinLZLGdPvTlr22YDfU-B30z7MQxlb8vng'
  end
end

RSpec.configure do |config|
  config.include ForestAdminTestToolkit::Factory::Collection
  config.include ForestAdminTestToolkit::Factory::Datasource
  config.include ForestAdminTestToolkit::Factory::Column

  config.before do
    cache = FileCache.new('app', 'tmp/cache/forest_admin')
    cache.clear

    agent_factory = ForestAdminAgent::Builder::AgentFactory.instance
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
