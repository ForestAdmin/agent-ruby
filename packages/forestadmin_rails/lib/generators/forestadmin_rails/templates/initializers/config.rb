ForestadminRails.configure do |config|
  config.auth_secret = '<%= @auth_secret %>'
  config.env_secret = '<%= @env_secret %>'
end
