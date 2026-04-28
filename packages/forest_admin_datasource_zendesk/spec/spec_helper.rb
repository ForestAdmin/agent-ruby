require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  enable_coverage :branch
  minimum_coverage 90
end

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
