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
  # @option options [Hash] :introspection Pre-defined schema introspection for resilient deployment
  #   - When provided, allows the datasource to start even if the RPC slave is unreachable
  #   - The introspection will be used as fallback when the slave connection fails
  #   - Schema polling will still be enabled to pick up changes when the slave becomes available
  #
  # @return [ForestAdminDatasourceRpc::Datasource] The configured datasource with schema polling
  def self.build(options)
    uri = options[:uri]
    auth_secret = options[:auth_secret] || ForestAdminAgent::Facades::Container.cache(:auth_secret)
    provided_introspection = options[:introspection]

    # Create schema polling client with configurable polling interval
    # Priority: options[:schema_polling_interval] > ENV['SCHEMA_POLLING_INTERVAL_SEC'] > default (600)
    polling_interval = if options[:schema_polling_interval_sec]
                         options[:schema_polling_interval]
                       elsif ENV['SCHEMA_POLLING_INTERVAL_SEC']
                         ENV['SCHEMA_POLLING_INTERVAL_SEC'].to_i
                       else
                         600 # 10 minutes by default
                       end

    polling_options = {
      polling_interval: polling_interval
    }

    schema_polling = Utils::SchemaPollingClient.new(uri, auth_secret, polling_options, provided_introspection) do
      # Callback when schema change is detected
      logger = ForestAdminAgent::Facades::Container.logger
      logger.log('Info', '[RPCDatasource] Schema change detected, reloading agent...')
      ForestAdminAgent::Builder::AgentFactory.instance.reload!
    end

    # Start polling (includes initial synchronous schema fetch)
    # The initial fetch is blocking, then async polling starts
    schema_polling.start

    # Get the schema from the polling client
    schema = schema_polling.current_schema

    # Use provided introspection as fallback when slave is unreachable
    if schema.nil? && provided_introspection
      ForestAdminAgent::Facades::Container.logger.log(
        'Warn',
        "RPC agent at #{uri} is unreachable, using provided introspection for resilient deployment."
      )
      options.delete(:introspection)
      schema = provided_introspection
    end

    if schema.nil?
      # return empty datasource for not breaking stack
      ForestAdminDatasourceToolkit::Datasource.new
    else
      ForestAdminDatasourceRpc::Datasource.new(options, schema, schema_polling)
    end
  end
end
