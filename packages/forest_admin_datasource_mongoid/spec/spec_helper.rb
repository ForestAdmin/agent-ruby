require 'simplecov'
require 'simplecov_json_formatter'
require 'simplecov-html'
require 'forest_admin_datasource_mongoid'
require 'mongoid-rspec'

SimpleCov.formatters = [SimpleCov::Formatter::JSONFormatter, SimpleCov::Formatter::HTMLFormatter]
SimpleCov.start do
  add_filter 'spec'
end

ENV['RAILS_ENV'] ||= 'test'

require File.expand_path('dummy/config/environment', __dir__)
Mongoid.load!(File.expand_path('dummy/config/mongoid.yml', __dir__), :test)
Mongoid.logger.level = Logger::ERROR
Mongo::Logger.logger.level = Logger::ERROR

RSpec.configure do |config|
  config.include Mongoid::Matchers, type: :model

  config.before(:suite) do
    Mongoid.purge!
  end

  config.after do
    Mongoid.purge!
  end

  # config.infer_spec_type_from_file_location!
  # config.filter_rails_from_backtrace!
end
