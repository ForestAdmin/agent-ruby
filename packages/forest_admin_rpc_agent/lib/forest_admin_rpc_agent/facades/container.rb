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
        instance.resolve(:logger)
      end

      def self.config_from_cache
        instance.resolve(:cache).get('config')
      end

      def self.cache(key)
        raise "Key #{key} not found in container" unless config_from_cache.key?(key)

        config_from_cache[key]
      end
    end
  end
end
