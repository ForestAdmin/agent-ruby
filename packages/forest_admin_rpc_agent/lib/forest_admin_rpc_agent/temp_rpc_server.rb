require 'sinatra'
require 'json'

set :port, 5000

get '/users' do
  content_type :json

  [
    { id: '1', email: 'rick@sanchez.com', first_name: 'Rick', last_name: 'Sanchez' },
    { id: '2', email: 'morty@smith.com', first_name: 'Morty', last_name: 'Smith' },
    { id: '3', email: 'summer@smith.com', first_name: 'Summer', last_name: 'Smith' },
    { id: '4', email: 'beth@smith.com', first_name: 'Beth', last_name: 'Smith' },
    { id: '5', email: 'jerry@smith.com', first_name: 'Jerry', last_name: 'Smith' }
  ].to_json
end

puts '✅ HTTP Server running on http://localhost:5000'
