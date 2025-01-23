require 'simplecov'
require 'simplecov_json_formatter'
require 'simplecov-html'
require 'forest_admin_datasource_toolkit'
require 'forest_admin_datasource_mongoid'
require 'mongoid-rspec'

SimpleCov.formatters = [SimpleCov::Formatter::JSONFormatter, SimpleCov::Formatter::HTMLFormatter]
SimpleCov.start do
  add_filter 'spec'
end

ENV['RAILS_ENV'] ||= 'test'

require File.expand_path('dummy/config/environment', __dir__)
Dir[File.expand_path('dummy/app/models/**/*.rb', __dir__)].each { |file| require file }

Mongoid.logger.level = Logger::ERROR
Mongo::Logger.logger.level = Logger::ERROR

RSpec.configure do |config|
  config.include Mongoid::Matchers, type: :model

  config.before(:suite) do
    Mongoid.load!(File.expand_path('dummy/config/mongoid.yml', __dir__), :test)
  end

  config.after do
    Mongoid.purge!
  end
end
