require_relative 'forest_admin_datasource_rpc/version'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/models")
loader.setup

module ForestAdminDatasourceRpc
  class Error < StandardError; end

  def self.configure_polling_pool(max_threads:)
    Utils::SchemaPollingPool.instance.configure(max_threads: max_threads)
  end

  def self.build(options)
    uri = options[:uri]
    auth_secret = options[:auth_secret] || ForestAdminAgent::Facades::Container.cache(:auth_secret)
    provided_introspection = options[:introspection]

    polling_interval = if options[:schema_polling_interval_sec]
                         options[:schema_polling_interval_sec]
                       elsif ENV['SCHEMA_POLLING_INTERVAL_SEC']
                         ENV['SCHEMA_POLLING_INTERVAL_SEC'].to_i
                       else
                         600
                       end

    # Auto-configure pool with default settings if not already configured
    ensure_pool_configured

    schema_polling = Utils::SchemaPollingClient.new(
      uri,
      auth_secret,
      polling_interval: polling_interval,
      introspection_schema: provided_introspection
    ) do
      logger = ForestAdminAgent::Facades::Container.logger
      logger.log('Info', '[RPCDatasource] Schema change detected, reloading agent...')
      ForestAdminAgent::Builder::AgentFactory.instance.reload!
    end

    # Start polling (includes initial synchronous schema fetch)
    # - Without introspection: crashes if RPC is unreachable
    # - With introspection: falls back to introspection if RPC is unreachable
    schema_polling.start?

    ForestAdminDatasourceRpc::Datasource.new(options, schema_polling.current_schema, schema_polling)
  end

  def self.ensure_pool_configured
    pool = Utils::SchemaPollingPool.instance
    return if pool.configured

    # Auto-configure with default of 1 thread if user hasn't configured
    pool.configure(max_threads: 1)
  end

  private_class_method :ensure_pool_configured
end
