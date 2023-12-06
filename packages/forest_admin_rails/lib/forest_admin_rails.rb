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

  setting :debug, default: true
  setting :auth_secret
  setting :env_secret
  setting :forest_server_url, default: 'https://api.forestadmin.com'
  setting :is_production, default: Rails.env.production?
  setting :prefix, default: 'forest'
  setting :permission_expiration, default: 900
  setting :cache_dir, default: :'tmp/cache/forest_admin'
  setting :schema_path, default: File.join(Dir.pwd, '.forestadmin-schema.json')
  setting :project_dir, default: Dir.pwd
  setting :loggerLevel, default: 'info'
  setting :logger, default: nil
  setting :instant_cache_refresh, default: true # Rails.env.production?

  if defined?(Rails::Railtie)
    # logic for cors middleware,... here // or it might be into Engine
    //
  end
end
