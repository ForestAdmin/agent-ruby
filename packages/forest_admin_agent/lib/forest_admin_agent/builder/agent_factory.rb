require 'dry-container'
require 'filecache'
require 'json'

module ForestAdminAgent
  module Builder
    class AgentFactory
      include Singleton
      include ForestAdminAgent::Utils::Schema
      include ForestAdminDatasourceToolkit::Exceptions

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

      def add_datasource(datasource, options = {})
        @customizer.add_datasource(datasource, options)

        self
      end

      def remove_collection(names)
        @customizer.remove_collection(names)
      end

      def add_chart(name, &definition)
        @customizer.add_chart(name, &definition)

        self
      end

      def customize_collection(name, &handle)
        @customizer.customize_collection(name, handle)

        self
      end

      def build
        @container.register(:datasource, @customizer.datasource(@logger))
        send_schema
      end

      def reload!
        begin
          @customizer.reload!(logger: @logger)
        rescue StandardError => e
          @logger.log('Error', "Error reloading agent: #{e.message}")
          return
        end

        @container.register(:datasource, @customizer.datasource(@logger), replace: true)
        send_schema
      end

      def send_schema(force: false)
        if should_skip_schema_update? && !force
          log_schema_skip
          return
        end

        return unless @has_env_secret

        schema_path = Facades::Container.cache(:schema_path)

        if Facades::Container.cache(:is_production)
          unless schema_path && File.exist?(schema_path)
            raise ForestException, "Can't load #{schema_path}. Providing a schema is mandatory in production."
          end

          schema = JSON.parse(File.read(schema_path), symbolize_names: true)
        else
          generated = SchemaEmitter.generate(@container.resolve(:datasource))
          meta = SchemaEmitter.meta

          schema = {
            meta: meta,
            collections: generated
          }

          File.write(schema_path, JSON.pretty_generate(schema))
        end

        if (append_schema_path = Facades::Container.cache(:append_schema_path))
          begin
            append_schema_file = JSON.parse(File.read(append_schema_path), symbolize_names: true)
            schema[:collections] = schema[:collections] + append_schema_file[:collections]
          rescue StandardError => e
            raise "Can't load additional schema #{append_schema_path}: #{e.message}"
          end
        end

        post_schema(schema, force)
      end

      private

      def post_schema(schema, force)
        api_map = SchemaEmitter.serialize(schema)
        should_send = do_server_want_schema(api_map[:meta][:schemaFileHash])

        if should_send || force
          client = ForestAdminAgent::Http::ForestAdminApiRequester.new
          client.post('/forest/apimaps', api_map.to_json)
          schema_file_hash_cache = FileCache.new('app', @options[:cache_dir].to_s, TTL_SCHEMA)
          schema_file_hash_cache.get_or_set 'value' do
            api_map[:meta][:schemaFileHash]
          end
          @container.register(:schema_file_hash, schema_file_hash_cache)
          ForestAdminAgent::Facades::Container.logger.log('Info', 'schema was updated, sending new version')
        else
          @container.resolve(:logger)
          ForestAdminAgent::Facades::Container.logger.log('Info', 'Schema was not updated since last run')
        end
      end

      def do_server_want_schema(hash)
        client = ForestAdminAgent::Http::ForestAdminApiRequester.new

        begin
          response = client.post('/forest/apimaps/hashcheck', { schemaFileHash: hash }.to_json)
          body = JSON.parse(response.body)
          body['sendSchema']
        rescue JSON::ParserError
          raise ForestException, "Invalid JSON response from ForestAdmin server #{response.body}"
        rescue Faraday::Error => e
          client.handle_response_error(e)
        end
      end

      def build_container
        @container = Dry::Container.new
      end

      def build_cache
        @container.register(:cache, FileCache.new('app', @options[:cache_dir].to_s, TTL_SCHEMA))
        return unless @has_env_secret

        cache = @container.resolve(:cache)

        @options[:customize_error_message] =
          clean_option_value(@options[:customize_error_message], 'config.customize_error_message =')
        @options[:logger] = clean_option_value(@options[:logger], 'config.logger =')

        cache.set('config', @options.to_h)
      end

      def build_logger
        @logger = Services::LoggerService.new(@options[:logger_level], @options[:logger])
        @container.register(:logger, @logger)
      end

      def clean_option_value(option, prefix)
        return unless option

        source = option.source
        cleaned_option = source&.strip if source
        cleaned_option&.delete_prefix(prefix)&.strip
      end

      def should_skip_schema_update?
        Facades::Container.cache(:skip_schema_update) == true
      end

      def log_schema_skip
        @logger.log('Warn', '[ForestAdmin] Schema update skipped (skip_schema_update flag is true)')
        @logger.log('Info', "[ForestAdmin] Running in #{Facades::Container.cache(:is_production) ? 'production' : 'development'} mode")
      end
    end
  end
end
