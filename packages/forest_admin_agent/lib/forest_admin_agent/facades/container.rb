module ForestAdminAgent
  module Facades
    class Container
      def self.instance
        ForestAdminAgent::Builder::AgentFactory.instance.container
      end

      def self.config_from_cache
        instance.resolve(:cache).get('config')
      end

      def self.get(key)
        raise "Key #{key} not found in container" unless config_from_cache.key?(key)

        cache[key]
      end
    end
  end
end
