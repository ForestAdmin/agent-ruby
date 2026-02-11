module ForestAdminRpcAgent
  module Facades
    class Container
      def self.instance
        ForestAdminRpcAgent::Agent.instance.container
      end

      def self.datasource
        instance.resolve(:datasource) do
          ForestAdminDatasourceToolkit::Datasource.new
        end
      end

      def self.logger
        instance&.resolve(:logger)
      end

      def self.config_from_cache
        instance.resolve(:config)
      end

      def self.cache(key)
        config = config_from_cache
        raise "Key #{key} not found in config" unless config.key?(key)

        config[key]
      end
    end
  end
end
