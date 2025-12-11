require_relative 'forest_admin_datasource_rpc/version'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/models")
loader.setup

module ForestAdminDatasourceRpc
  class Error < StandardError; end

  # Build a RPC datasource with schema polling enabled.
  #
  # @param options [Hash] Configuration options
  # @option options [String] :uri The URI of the RPC agent
  # @option options [String] :auth_secret The authentication secret (optional, will use cache if not provided)
  # @option options [Integer] :schema_polling_interval Polling interval in seconds (optional)
  #   - Default: 600 seconds (10 minutes)
  #   - Can be overridden with ENV['SCHEMA_POLLING_INTERVAL_SEC']
  #   - Valid range: 1-3600 seconds
  #   - Priority: options[:schema_polling_interval] > ENV['SCHEMA_POLLING_INTERVAL_SEC'] > default
  #   - Example: SCHEMA_POLLING_INTERVAL_SEC=30 for development (30 seconds)
  #
  # @return [ForestAdminDatasourceRpc::Datasource] The configured datasource with schema polling
  def self.build(options)
    uri = options[:uri]
    auth_secret = options[:auth_secret] || ForestAdminAgent::Facades::Container.cache(:auth_secret)

    # Create schema polling client with configurable polling interval
    # Priority: options[:schema_polling_interval] > ENV['SCHEMA_POLLING_INTERVAL_SEC'] > default (600)
    polling_interval = if options[:schema_polling_interval]
                         options[:schema_polling_interval]
                       elsif ENV['SCHEMA_POLLING_INTERVAL_SEC']
                         ENV['SCHEMA_POLLING_INTERVAL_SEC'].to_i
                       else
                         600 # 10 minutes by default
                       end

    polling_options = {
      polling_interval: polling_interval
    }

    schema_polling = Utils::SchemaPollingClient.new(uri, auth_secret, polling_options) do
      # Callback when schema change is detected
      logger = ForestAdminAgent::Facades::Container.logger
      logger.log('Info', '[RPCDatasource] Schema change detected, reloading agent...')
      ForestAdminAgent::Builder::AgentFactory.instance.reload!
    end

    # Fetch initial schema synchronously (blocking call)
    # This also populates the ETag cache to avoid redundant fetch when polling starts
    schema = schema_polling.fetch_initial_schema

    if schema.nil?
      # return empty datasource for not breaking stack
      ForestAdminDatasourceToolkit::Datasource.new
    else
      # Start polling for schema changes
      # Since we already have the schema and ETag, polling will wait before the first check
      schema_polling.start

      datasource = ForestAdminDatasourceRpc::Datasource.new(options, schema, schema_polling)

      # Setup cleanup hooks for proper schema polling client shutdown
      setup_cleanup_hooks(datasource)

      datasource
    end
  end

  def self.setup_cleanup_hooks(datasource)
    # Register cleanup handler for graceful shutdown
    at_exit do
      datasource.cleanup
    rescue StandardError => e
      # Silently ignore errors during exit cleanup to prevent test pollution
      warn "[RPCDatasource] Error during at_exit cleanup: #{e.message}" if $VERBOSE
    end

    # Handle SIGINT (Ctrl+C)
    Signal.trap('INT') do
      begin
        ForestAdminAgent::Facades::Container.logger&.log('Info', '[RPCDatasource] Received SIGINT, cleaning up...')
      rescue StandardError
        # Logger might not be available
      end
      datasource.cleanup
      exit(0)
    end

    # Handle SIGTERM (default kill signal)
    Signal.trap('TERM') do
      begin
        ForestAdminAgent::Facades::Container.logger&.log('Info', '[RPCDatasource] Received SIGTERM, cleaning up...')
      rescue StandardError
        # Logger might not be available
      end
      datasource.cleanup
      exit(0)
    end
  end
end
