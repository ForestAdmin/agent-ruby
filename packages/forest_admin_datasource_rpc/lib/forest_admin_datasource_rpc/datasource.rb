module ForestAdminDatasourceRpc
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    include ForestAdminDatasourceRpc::Utils

    attr_reader :shared_rpc_client, :rpc_relations

    def initialize(options, introspection, schema_polling_client = nil)
      super()

      ForestAdminAgent::Facades::Container.logger.log(
        'Info',
        "Building Rpc Datasource with #{introspection[:collections].length} " \
        "collections and #{introspection[:charts].length} charts."
      )

      @shared_rpc_client = RpcClient.new(
        options[:uri],
        options[:auth_secret] || ForestAdminAgent::Facades::Container.cache(:auth_secret)
      )

      introspection[:collections].each do |schema|
        add_collection(Collection.new(self, schema[:name], schema))
      end

      @charts = introspection[:charts]
      @rpc_relations = introspection[:rpc_relations]
      @schema_polling_client = schema_polling_client
      @cleaned_up = false

      native_query_connections = introspection[:native_query_connections] || []
      @live_query_connections = native_query_connections.to_h { |conn| [conn[:name], conn[:name]] }

      @schema = { charts: @charts }

      # Register shutdown hook to cleanup schema polling gracefully
      register_shutdown_hook if @schema_polling_client
    end

    def render_chart(caller, name)
      url = 'forest/rpc-datasource-chart'

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding datasource chart '#{name}' call to the Rpc agent on #{url}."
      )

      @shared_rpc_client.call_rpc(url, caller: caller, method: :post, payload: { chart: name })
    end

    def execute_native_query(connection_name, query, binds)
      url = 'forest/rpc-native-query'

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding native query for connection '#{connection_name}' to the Rpc agent on #{url}."
      )

      result = @shared_rpc_client.call_rpc(
        url,
        method: :post,
        payload: { connection_name: connection_name, query: query, binds: binds }
      )
      ForestAdminDatasourceToolkit::Utils::HashHelper.convert_keys(result.to_a)
    end

    def cleanup
      return if @cleaned_up

      @cleaned_up = true

      if @schema_polling_client
        log_info('[RPCDatasource] Stopping schema polling...')
        @schema_polling_client.stop
        log_info('[RPCDatasource] Schema polling stopped')
      end
    rescue StandardError => e
      log_error("[RPCDatasource] Error during cleanup: #{e.class} - #{e.message}")
    end

    private

    def register_shutdown_hook
      # Register at_exit hook for graceful shutdown
      # This ensures schema polling is stopped when the application exits
      at_exit do
        cleanup
      end
    end

    def log_info(message)
      return unless defined?(ForestAdminAgent::Facades::Container)

      ForestAdminAgent::Facades::Container.logger&.log('Info', message)
    rescue StandardError
      # Silently ignore logging errors during shutdown
    end

    def log_error(message)
      return unless defined?(ForestAdminAgent::Facades::Container)

      ForestAdminAgent::Facades::Container.logger&.log('Error', message)
    rescue StandardError
      # Silently ignore logging errors during shutdown
    end
  end
end
