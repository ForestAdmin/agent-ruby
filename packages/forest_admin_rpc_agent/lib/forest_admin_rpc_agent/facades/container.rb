module ForestAdminRpcAgent
  module Facades
    class Container
      def self.instance
        # Try RpcAgent first, fallback to AgentFactory (for masters using RPC datasource)
        if ForestAdminRpcAgent::Agent.instance.container
          ForestAdminRpcAgent::Agent.instance.container
        elsif defined?(ForestAdminAgent::Builder::AgentFactory) && ForestAdminAgent::Builder::AgentFactory.instance.container
          ForestAdminAgent::Builder::AgentFactory.instance.container
        else
          ForestAdminRpcAgent::Agent.instance.container  # Will be nil but maintains original behavior
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
