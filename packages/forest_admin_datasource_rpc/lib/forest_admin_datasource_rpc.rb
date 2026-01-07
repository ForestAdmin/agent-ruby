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
    provided_introspection_etag = options[:introspection_etag]

    polling_interval = options[:schema_polling_interval_sec] ||
                       ENV['SCHEMA_POLLING_INTERVAL_SEC']&.to_i ||
                       600

    # Auto-configure pool with default settings if not already configured
    ensure_pool_configured

    schema_polling = Utils::SchemaPollingClient.new(
      uri,
      auth_secret,
      polling_interval: polling_interval,
      introspection_schema: provided_introspection,
      introspection_etag: provided_introspection_etag
    ) do
      Thread.new do
        logger = ForestAdminAgent::Facades::Container.logger
        logger.log('Info', '[RPCDatasource] Schema change detected, reloading agent in background...')
        begin
          ForestAdminAgent::Builder::AgentFactory.instance.reload!
          logger.log('Info', '[RPCDatasource] Agent reload completed successfully')
        rescue StandardError => e
          logger.log('Error', "[RPCDatasource] Agent reload failed: #{e.class} - #{e.message}")
        end
      end
    end

    # Start polling (includes initial synchronous schema fetch)
    # - Without introspection: crashes if RPC is unreachable
    # - With introspection: falls back to introspection if RPC is unreachable
    schema_polling.start?

    schema = schema_polling.current_schema
    if schema.nil?
      raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
            'Fatal: Unable to build RPC datasource - no introspection schema was provided and schema fetch failed'
    end

    options.delete(:introspection)
    ForestAdminDatasourceRpc::Datasource.new(options, schema, schema_polling)
  end

  def self.ensure_pool_configured
    pool = Utils::SchemaPollingPool.instance
    return if pool.configured

    # Auto-configure with default thread count if user hasn't configured
    pool.configure(max_threads: Utils::SchemaPollingPool::DEFAULT_MAX_THREADS)
  end

  private_class_method :ensure_pool_configured
end
