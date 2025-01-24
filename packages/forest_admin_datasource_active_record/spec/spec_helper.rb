require 'simplecov'
require 'simplecov_json_formatter'
require 'simplecov-html'
require 'forest_admin_datasource_active_record'
require 'active_record'
require 'database_cleaner-active_record'

SimpleCov.formatters = [SimpleCov::Formatter::JSONFormatter, SimpleCov::Formatter::HTMLFormatter]
SimpleCov.start do
  add_filter 'spec'
end
puts "Current working directory: #{Dir.pwd}"
SimpleCov.coverage_dir File.join(Dir.pwd, 'packages/forest_admin_datasource_active_record/coverage')
SimpleCov.at_exit do
  result = SimpleCov.result
  coverage_file = File.join(SimpleCov.coverage_dir, 'coverage.json')
  coverage_percent = result.covered_percent
  puts "Coverage Report Generated"
  puts "Coverage file generated at: #{coverage_file}"
  puts "Covered Percent: #{coverage_percent}%"
end

ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('dummy/config/environment', __dir__)
Rails.application.eager_load!

ActiveRecord::Migration.verbose = false
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: 'db/database.db')
ActiveRecord::MigrationContext.new("spec/dummy/db/migrate").migrate

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # database_cleaner config
  config.before(:suite) do
    DatabaseCleaner.clean_with :truncation, except: %w[ar_internal_metadata]
  end

  config.before do
    DatabaseCleaner.strategy = :transaction
  end

  config.before do
    DatabaseCleaner.start
  end

  config.after do
    DatabaseCleaner.clean
  end
end
