ForestAdminRails.configure do |config|
  config.forest_server_url = ENV['FOREST_SERVER_URL']
  config.auth_secret = ENV['FOREST_AUTH_SECRET']
  config.env_secret = ENV['FOREST_ENV_SECRET']
end
