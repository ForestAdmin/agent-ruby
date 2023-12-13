require 'dry-container'
require 'filecache'

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
        @customizer = ForestAdminDatasourceCustomizer::DatasourceCustomizer.new
        build_container
        build_cache
        build_logger
      end

      def add_datasource(datasource)
        datasource.collections.each_value { |collection| @customizer.add_collection(collection) }
        self
      end

      def customize_collection(name, handle)
        @customizer.customize_collection(name, handle)
      end

      def build
        @container.register(:datasource, @customizer)
        send_schema
      end

      def send_schema(force: false)
        return unless @has_env_secret

        schema = ForestAdminAgent::Utils::Schema::SchemaEmitter.get_serialized_schema(@customizer)
        schema_is_know = @container.key?(:schema_file_hash) &&
                         @container.resolve(:schema_file_hash).get('value') == schema[:meta][:schemaFileHash]

        if !schema_is_know || force
          #   Logger::log('Info', 'schema was updated, sending new version');
          client = ForestAdminAgent::Http::ForestAdminApiRequester.new
          client.post('/forest/apimaps', schema.to_json)
          schema_file_hash_cache = FileCache.new('app', @options[:cache_dir].to_s, TTL_SCHEMA)
          schema_file_hash_cache.get_or_set 'value' do
            schema[:meta][:schemaFileHash]
          end
          @container.register(:schema_file_hash, schema_file_hash_cache)
        else
          @container.resolve(:logger)
          # TODO:  Logger::log('Info', 'Schema was not updated since last run');
        end
      end

      private

      def build_container
        @container = Dry::Container.new
      end

      def build_cache
        @container.register(:cache, FileCache.new('app', @options[:cache_dir].to_s, TTL_SCHEMA))
        return unless @has_env_secret

        cache = @container.resolve(:cache)
        cache.set('config', @options.to_h)
      end

      def build_logger
        logger = Services::LoggerService.new(@options[:loggerLevel], @options[:logger])
        @container.register(:logger, logger)
      end
    end
  end
end
