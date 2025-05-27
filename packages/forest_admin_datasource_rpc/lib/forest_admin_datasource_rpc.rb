require_relative 'forest_admin_datasource_rpc/version'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/models")
loader.setup

module ForestAdminDatasourceRpc
  class Error < StandardError; end

  def self.build(options)
    uri = options[:uri]
    auth_secret = ForestAdminRpcAgent::Facades::Container.cache(:auth_secret)
    ForestAdminRpcAgent::Facades::Container.logger.log('Info', "Getting schema from RPC agent on #{uri}.")

    begin
      rpc_client = Utils::RpcClient.new(uri, auth_secret)
      schema = rpc_client.call_rpc('/forest/rpc-schema', method: :get, symbolize_keys: true)
      last_hash_schema = Digest::SHA1.hexdigest(schema.to_h.to_s)
    rescue StandardError
      ForestAdminRpcAgent::Facades::Container.logger.log(
        'Error',
        'Failed to get schema from RPC agent. Please check the RPC agent is running.'
      )
    end

    if schema.nil?
      # return empty datasource for not breaking stack
      ForestAdminDatasourceToolkit::Datasource.new
    else
      sse = Utils::SseClient.new("#{uri}/forest/rpc/sse", auth_secret) do
        ForestAdminRpcAgent::Facades::Container.logger.log('Info', 'RPC server stopped, checking schema...')
        new_schema = rpc_client.call_rpc('/forest/rpc-schema', method: :get, symbolize_keys: true)

        if last_hash_schema == Digest::SHA1.hexdigest(new_schema.to_h.to_s)
          ForestAdminRpcAgent::Facades::Container.logger.log('Debug', '[RPCDatasource] Schema has not changed')
        else
          ForestAdminAgent::Builder::AgentFactory.instance.reload!
        end
      end
      sse.start

      ForestAdminDatasourceRpc::Datasource.new(options, schema)
    end
  end
end
