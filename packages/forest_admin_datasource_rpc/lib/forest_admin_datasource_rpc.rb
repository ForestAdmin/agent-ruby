require_relative 'forest_admin_datasource_rpc/version'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/models")
loader.setup

module ForestAdminDatasourceRpc
  class Error < StandardError; end

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

    polling_options = {
      polling_interval: polling_interval
    }

    schema_polling = Utils::SchemaPollingClient.new(uri, auth_secret, polling_options, provided_introspection) do
      logger = ForestAdminAgent::Facades::Container.logger
      logger.log('Info', '[RPCDatasource] Schema change detected, reloading agent...')
      ForestAdminAgent::Builder::AgentFactory.instance.reload!
    end

    schema_polling.start
    schema = schema_polling.current_schema

    if schema.nil? && provided_introspection
      ForestAdminAgent::Facades::Container.logger.log(
        'Warn',
        "RPC agent at #{uri} is unreachable, using provided introspection for resilient deployment."
      )
      options.delete(:introspection)
      schema = provided_introspection
    end

    if schema.nil?
      raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
            "Fatal: Unable to build RPC datasource for #{uri}. " \
            "The RPC agent is unreachable and no introspection schema was provided. " \
            "Please ensure the RPC agent is running or provide an introspection schema for resilient deployment."
    else
      ForestAdminDatasourceRpc::Datasource.new(options, schema, schema_polling)
    end
  end
end
