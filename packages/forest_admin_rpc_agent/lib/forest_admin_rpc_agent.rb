require 'dry-configurable'
require 'forest_admin_rpc_agent/version'
require 'forest_admin_agent'
require 'forest_admin_datasource_customizer'
require 'forest_admin_datasource_toolkit'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.setup

module ForestAdminRpcAgent
  extend Dry::Configurable

  setting :debug, default: true
  setting :auth_secret
  setting :env_secret
  setting :forest_server_url, default: 'https://api.forestadmin.com'
  setting :is_production, default: false
  setting :prefix, default: nil
  setting :permission_expiration, default: 900
  setting :cache_dir, default: :'tmp/cache/forest_admin'
  setting :schema_path, default: File.join(Dir.pwd, '.forestadmin-schema.json')
  setting :project_dir, default: Dir.pwd
  setting :loggerLevel, default: 'info'
  setting :logger, default: nil
  setting :customize_error_message, default: nil
  setting :instant_cache_refresh, default: false

  begin
    require 'thor'
    require 'forest_admin_rpc_agent/thor/install'
  rescue LoadError
    # Thor is not available, skip loading commands
  end
end
