require 'dry-configurable'
require 'forest_admin_rails/version'
require 'forest_admin_rails/engine'
require 'zeitwerk'
require 'rails/railtie'
require 'forest_admin_agent'

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/generators")
loader.setup

module ForestAdminRails
  extend Dry::Configurable

  setting :debug, default: ENV['FOREST_DEBUG'] || true
  setting :auth_secret
  setting :env_secret
  setting :forest_server_url, default: ENV['FOREST_SERVER_URL'] || 'https://api.forestadmin.com'
  setting :is_production, default: (ENV['FOREST_ENVIRONMENT'] || 'dev') == 'prod'
  setting :prefix, default: ENV['FOREST_PREFIX'] || 'forest'
  setting :permission_expiration, default: ENV['FOREST_PERMISSIONS_EXPIRATION_IN_SECONDS'] || 300
  setting :cache_dir, default: :'tmp/cache/forest_admin'
  setting :schema_path # , default: app_root.join('.forest_admin-schema.json')
  setting :project_dir # , default: app_root
  setting :loggerLevel, default: ENV['FOREST_LOGGER_LEVEL'] || 'info'
  setting :logger, default: nil

  if defined?(Rails::Railtie)
    # logic for cors middleware,... here // or it might be into Engine
  end

  def app_root
    @app_root ||= (defined?(::Rails.root) && !::Rails.root.nil? ? Rails.root.to_s : Dir.pwd).to_s
  end
end
