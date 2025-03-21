require 'bundler/setup'
Bundler.require

require 'sinatra/activerecord'
require 'sinatra'
require_relative 'config/forest_admin_sinatra'
require 'forest_admin_sinatra/extensions/sinatra_extension'

# load models
Dir["models/*.rb"].each {|file| require_relative file.remove('.rb') }

# setup databse
set :database, {adapter: "sqlite3", database: "database.sqlite3"}

# setup FOREST AGENT
database_configuration = ActiveRecord::Base.connection_db_config
datasource = ForestAdminDatasourceActiveRecord::Datasource.new(database_configuration)
agent = ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
agent.build

get '/' do
  'Welcome on forest Sinatra app example'
end
