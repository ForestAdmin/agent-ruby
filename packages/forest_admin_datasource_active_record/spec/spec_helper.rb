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

SimpleCov.coverage_dir 'coverage'
SimpleCov.at_exit do
  result = SimpleCov.result
  result.format!
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
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with :truncation
  end

  config.around(:each, :db_truncation) do |example|
    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end
