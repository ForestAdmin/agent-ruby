require 'dry-container'
require 'lightly'

module ForestAdminAgent
  module Builder
    class AgentFactory
      include Singleton

      TTL_CONFIG = 3600
      TTL_SCHEMA = 7200

      attr_reader :customizer, :container, :has_env_secret

      def setup(options)
        @options = options
        @has_env_secret = options.to_h.key?(:env_secret)
        @customizer = ForestAdminDatasourceToolkit::Datasource.new
        build_container
        build_cache
        build_logger
      end

      def add_datasource(datasource)
        datasource.collections.each { |_name, collection| @customizer.add_collection(collection) }
        self
      end

      def build
        @container.register(:datasource, @customizer)
        send_schema
      end

      private

      def send_schema(force: false)
        return unless @has_env_secret

        schema = ForestAdminAgent::Utils::Schema::SchemaEmitter.get_serialized_schema(@customizer)
        schema_is_know = false
        # if (Cache::get('schemaFileHash') === $schema['meta']['schemaFileHash']) {
        #   $schemaIsKnown = true;
        # }

        if !schema_is_know || force
          #   Logger::log('Info', 'schema was updated, sending new version');
          client = ForestAdminAgent::Http::ForestAdminApiRequester.new
          client.post('/forest/apimaps', schema)
        else
          @container.resolve(:logger)
          # TODO:  Logger::log('Info', 'Schema was not updated since last run');
        end
      end

      def build_container
        @container = Dry::Container.new
      end

      def build_cache
        @container.register(:cache, Lightly.new(life: TTL_CONFIG, dir: @options[:cache_dir].to_s))
        return unless @has_env_secret

        cache = @container.resolve(:cache)
        cache.get 'config' do
          @options.to_h
        end
      end

      def build_logger
        logger = Services::LoggerService.new(@options[:loggerLevel], @options[:logger])
        @container.register(:logger, logger)
      end
    end
  end
end
