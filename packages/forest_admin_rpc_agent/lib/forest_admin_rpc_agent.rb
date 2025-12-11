require 'dry-configurable'
require 'forest_admin_rpc_agent/version'
require 'forest_admin_rpc_agent/engine' if defined?(Rails)
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
  setting :cache_dir, default: :'tmp/cache/forest_admin'
  setting :project_dir, default: Dir.pwd
  setting :schema_path, default: File.join(Dir.pwd, '.forestadmin-rpc-schema.json')
  setting :skip_schema_update, default: false
  setting :logger_level, default: 'info'
  setting :logger, default: nil
  setting :customize_error_message, default: nil
  setting :disable_route_cache, default: false

  begin
    require 'thor'
    require 'forest_admin_rpc_agent/thor/install'
  rescue LoadError
    # Thor is not available, skip loading commands
  end
end
