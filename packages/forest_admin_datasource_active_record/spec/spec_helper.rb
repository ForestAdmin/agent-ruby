require 'simplecov'
require 'simplecov_json_formatter'
require 'simplecov-html'
require 'forest_admin_datasource_active_record'
require 'active_record'
require 'database_cleaner-active_record'

SimpleCov.formatters = [SimpleCov::Formatter::JSONFormatter, SimpleCov::Formatter::HTMLFormatter]
SimpleCov.start  do
  add_filter 'spec'
  add_group "Lib", "lib"
end

ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../dummy/config/environment', __FILE__)
Rails.application.eager_load!

ActiveRecord::Migration.verbose = false
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: 'db/database.db')
ActiveRecord::MigrationContext.new("db/migrate").migrate

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
