require_relative 'forest_admin_datasource_rpc/version'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/models")
loader.setup

module ForestAdminDatasourceRpc
  class Error < StandardError; end

  def self.build(options)
    uri = options[:uri]
    ForestAdminRpcAgent::Facades::Container.logger.log('Info', "Getting schema from RPC agent on #{uri}.")

    begin
      schema = Utils::RpcClient.new(uri, ForestAdminAgent::Facades::Container.cache(:auth_secret))
                               .call_rpc('/forest/rpc-schema', method: :get, symbolize_keys: true)
    rescue StandardError
      raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
            'Failed to get schema from RPC agent. Please check the RPC agent is running.'
    end

    ForestAdminDatasourceRpc::Datasource.new(options, schema)
  end
end
