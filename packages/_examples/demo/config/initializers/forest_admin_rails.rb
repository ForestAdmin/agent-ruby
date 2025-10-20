ForestAdminRails.configure do |config|
  config.forest_server_url = ENV['FOREST_SERVER_URL']
  config.auth_secret = ENV['FOREST_AUTH_SECRET']
  config.env_secret = ENV['FOREST_ENV_SECRET']
  # config.prefix = ''
  # config.customize_error_message = proc { |_error| '' }

  # Skip schema update in serverless/multi-instance environments
  # config.skip_schema_update = ENV['SKIP_FOREST_SCHEMA_UPDATE'] == 'true'
end
