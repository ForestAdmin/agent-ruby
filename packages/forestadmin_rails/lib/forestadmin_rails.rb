require 'dry-configurable'
require "forestadmin_rails/version"
require "forestadmin_rails/engine"
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/generators")
loader.setup

module ForestadminRails
  extend Dry::Configurable

  setting :debug, default: ENV['FOREST_DEBUG'] || true
  setting :auth_secret
  setting :env_secret
  setting :forest_server_url, default: ENV['FOREST_SERVER_URL'] || 'https://api.forestadmin.com'
  setting :is_production, default: (ENV['FOREST_ENVIRONMENT'] || 'dev') == 'prod'
  setting :prefix, default: ENV['FOREST_PREFIX'] || 'forest'
  setting :permission_expiration, default: ENV['FOREST_PERMISSIONS_EXPIRATION_IN_SECONDS'] || 300
  setting :cache_dir, default: :memory_store
  setting :schema_path # , default: Rails.root.join('.forestadmin-schema.json')
  setting :project_dir # , default: Rails.root
end
