require_relative 'forest_admin_datasource_rpc/version'
require 'zeitwerk'
require 'Json'

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/models")
loader.setup

module ForestAdminDatasourceRpc
  class Error < StandardError; end

  def self.build(options)
    uri = options[:uri]
    ForestAdminRpcAgent::Facades::Container.logger.log('Info', "Getting schema from Rpc agent on #{uri}.")

    schema = Utils::RpcClient.new(uri, ForestAdminAgent::Facades::Container.cache(:auth_secret))
                             .call_rpc('/forest/rpc-schema', method: :get, symbolize_keys: true)

    ForestAdminDatasourceRpc::Datasource.new(options, schema)
  end
end
