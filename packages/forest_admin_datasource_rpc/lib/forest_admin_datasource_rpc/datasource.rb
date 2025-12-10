module ForestAdminDatasourceRpc
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    include ForestAdminDatasourceRpc::Utils

    def initialize(options, introspection, schema_polling_client = nil)
      super()

      ForestAdminAgent::Facades::Container.logger.log(
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
      @schema_polling_client = schema_polling_client
      @cleaned_up = false

      native_query_connections = introspection[:native_query_connections] || []
      @live_query_connections = native_query_connections.to_h { |conn| [conn[:name], conn[:name]] }

      @schema = { charts: @charts }
    end

    def render_chart(caller, name)
      client = RpcClient.new(@options[:uri], @options[:auth_secret] || ForestAdminAgent::Facades::Container.cache(:auth_secret))
      url = 'forest/rpc-datasource-chart'

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding datasource chart '#{name}' call to the Rpc agent on #{url}."
      )

      client.call_rpc(url, caller: caller, method: :post, payload: { chart: name }).body
    end

    def execute_native_query(connection_name, query, binds)
      client = RpcClient.new(@options[:uri], @options[:auth_secret] || ForestAdminAgent::Facades::Container.cache(:auth_secret))
      url = 'forest/rpc-native-query'

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding native query for connection '#{connection_name}' to the Rpc agent on #{url}."
      )

      result = client.call_rpc(url, method: :post,
                                    payload: { connection_name: connection_name, query: query, binds: binds }).body
      ForestAdminDatasourceToolkit::Utils::HashHelper.convert_keys(result.to_a)
    end

    def cleanup
      return if @cleaned_up

      @cleaned_up = true

      if @schema_polling_client
        ForestAdminAgent::Facades::Container.logger&.log('Info', '[RPCDatasource] Stopping schema polling...')
        @schema_polling_client.stop
        ForestAdminAgent::Facades::Container.logger&.log('Info', '[RPCDatasource] Schema polling stopped')
      end
    rescue StandardError => e
      ForestAdminAgent::Facades::Container.logger&.log(
        'Error',
        "[RPCDatasource] Error during cleanup: #{e.class} - #{e.message}"
      )
    end
  end
end
