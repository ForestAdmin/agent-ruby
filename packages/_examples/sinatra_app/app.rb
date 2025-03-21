require 'bundler/setup'
Bundler.require

require 'sinatra'
require 'sinatra/activerecord'

# load models
Dir["models/*.rb"].each {|file| require_relative file.remove('.rb') }

# setup databse
set :database, {adapter: "sqlite3", database: "database.sqlite3"}

get '/' do
  'Welcome on forest Sinatra app example'
end
