module ForestAdminDatasourceRpc
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    include ForestAdminDatasourceRpc::Utils

    def initialize(options, introspection)
      super()

      ForestAdminRpcAgent::Facades::Container.logger.log(
        'Info',
        "Building Rpc Datasource with #{introspection[:collections].length} " \
        "collections and #{introspection[:charts].length} charts."
      )

      introspection[:collections].each do |schema|
        add_collection(Collection.new(self, schema[:name], options, schema))
      end

      @options = options
      @charts = introspection[:charts]
      @rpc_relations = introspection[:rpc_relations]

      @schema = { charts: @charts }
    end

    def render_chart(caller, name)
      client = RpcClient.new(@options[:uri], ForestAdminRpcAgent::Facades::Container.cache(:auth_secret))
      url = 'forest/rpc/datasource-chart'

      ForestAdminRpcAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding datasource chart '#{name}' call to the Rpc agent on #{url}."
      )

      client.call_rpc(url, method: :post, payload: { chart: name, caller: caller.to_h })
    end
  end
end
