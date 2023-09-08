require 'dry-container'

# TODO: move to a new agent package
module ForestadminRails
  module Registry
    class AgentFactory
      include Singleton

      TTL_CONFIG = 3600
      TTL_SCHEMA = 7200

      attr_reader :customizer, :container, :has_env_secret

      def setup(options)
        @options = options
        @has_env_secret = options.to_h.key?(:env_secret)
        # @customizer = DatasourceCustomizer.new
        build_container
        build_cache
        build_logger
      end

      def build
        # @customizer.datasource
        @container.register('datasource', {})
        send_schema
      end

      private

      def send_schema
        # todo
      end

      def build_container
        @container = Dry::Container.new
      end

      def build_cache; end

      def build_logger
        logger = LoggerService.new(@options[:loggerLevel], @options[:logger])
        @container.register('logger', logger)
      end
    end
  end
end
