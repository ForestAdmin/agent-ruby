module ForestAdminAgent
  module Facades
    class Container
      def self.instance
        # Try RpcAgent first (for RPC slaves), fallback to AgentFactory (for masters)
        if defined?(ForestAdminRpcAgent::Agent) && ForestAdminRpcAgent::Agent.instance.container
          ForestAdminRpcAgent::Agent.instance.container
        else
          ForestAdminAgent::Builder::AgentFactory.instance.container
        end
      end

      def self.datasource
        instance.resolve(:datasource) do
          ForestAdminDatasourceToolkit::Datasource.new
        end
      end

      def self.logger
        instance.resolve(:logger)
      end

      def self.config_from_cache
        instance.resolve(:config)
      end

      def self.cache(key)
        config = config_from_cache
        return nil unless config&.key?(key)

        config[key]
      end
    end
  end
end
