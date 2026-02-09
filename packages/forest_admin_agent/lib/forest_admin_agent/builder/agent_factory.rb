require 'dry-container'
require 'json'

module ForestAdminAgent
  module Builder
    class AgentFactory
      include Singleton
      include ForestAdminAgent::Utils::Schema
      include ForestAdminAgent::Http::Exceptions
      include ForestAdminDatasourceToolkit::Exceptions
      include ForestAdminDatasourceCustomizer::DSL::DatasourceHelpers

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
        @customizer.customize_collection(name, &handle)

        self
      end

      def use(plugin, options = {})
        @customizer.use(plugin, options)

        self
      end

      def build
        @container.register(:datasource, @customizer.datasource(@logger))

        # Reset route cache to ensure routes are computed with all customizations
        ForestAdminAgent::Http::Router.reset_cached_routes!

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

        # Reset route cache before sending schema to ensure routes are recomputed with all customizations
        ForestAdminAgent::Http::Router.reset_cached_routes!
        @logger.log('Info', 'route cache cleared due to agent reload')

        send_schema
      end

      def send_schema(force: false)
        if should_skip_schema_update? && !force
          log_schema_skip
          return
        end

        return unless @has_env_secret

        schema = generate_schema_file

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

      # Generates or loads the schema and writes it to file (in development mode).
      # This method can be overridden by subclasses that need to customize schema handling.
      # @return [Hash] The schema hash with :meta and :collections keys
      def generate_schema_file
        schema_path = Facades::Container.cache(:schema_path)

        if Facades::Container.cache(:is_production)
          unless schema_path && File.exist?(schema_path)
            raise InternalServerError.new(
              'Schema file not found in production',
              details: { schema_path: schema_path }
            )
          end

          JSON.parse(File.read(schema_path), symbolize_names: true)
        else
          datasource = @container.resolve(:datasource)
          schema = build_schema(datasource)
          write_schema_file(schema_path, schema)
          schema
        end
      end

      # Builds the schema hash from the datasource
      # @param datasource [Object] The datasource to generate schema from
      # @return [Hash] The schema hash with :meta and :collections keys
      def build_schema(datasource)
        generated = SchemaEmitter.generate(datasource)
        meta = SchemaEmitter.meta

        {
          meta: meta,
          collections: generated
        }
      end

      # Writes the schema to a file
      # @param schema_path [String] Path to write the schema file
      # @param schema [Hash] The schema to write
      def write_schema_file(schema_path, schema)
        File.write(schema_path, format_schema_json(schema))
      end

      private

      def format_schema_json(schema)
        # Custom JSON formatting that keeps single-element arrays on one line
        json = JSON.pretty_generate(schema)

        # Replace multiline arrays containing only ONE string with single-line format
        # This matches patterns like:
        # type: [
        #   "String"
        # ]
        # and replaces them with: type: ["String"]
        # Multi-element arrays (like enums) remain on multiple lines for readability
        json.gsub(/:\s*\[\n\s*("(?:[^"\\]|\\.)*")\n\s*\]/, ': [\1]')
      end

      def post_schema(schema, force)
        api_map = SchemaEmitter.serialize(schema)
        should_send = do_server_want_schema(api_map[:meta][:schemaFileHash])

        if should_send || force
          send_schema_to_server(api_map)
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
        rescue JSON::ParserError => e
          http_status = begin
            response.status
          rescue StandardError
            'unknown'
          end

          raise InternalServerError.new(
            "Invalid JSON response from ForestAdmin server (HTTP #{http_status}). " \
            "Expected JSON but received: #{response.body}",
            details: { body: response.body, status: http_status },
            cause: e
          )
        rescue Faraday::Error => e
          client.handle_response_error(e)
        end
      end

      def build_container
        @container = Dry::Container.new
      end

      def build_cache
        @options[:customize_error_message] =
          clean_option_value(@options[:customize_error_message], 'config.customize_error_message =')
        @options[:logger] = clean_option_value(@options[:logger], 'config.logger =')

        @container.register(:config, @options.to_h)

        configure_rpc_polling_pool if @options[:rpc_max_polling_threads]
      end

      def configure_rpc_polling_pool
        max_threads = @options[:rpc_max_polling_threads].to_i
        return unless max_threads.positive?

        return unless defined?(ForestAdminDatasourceRpc)

        ForestAdminDatasourceRpc.configure_polling_pool(max_threads: max_threads)
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
        environment = Facades::Container.cache(:is_production) ? 'production' : 'development'
        @logger.log('Info',
                    "[ForestAdmin] Running in #{environment} mode")
      end

      def send_schema_to_server(api_map)
        ForestAdminAgent::Facades::Container.logger.log('Info', 'schema was updated, sending new version')
        client = ForestAdminAgent::Http::ForestAdminApiRequester.new
        client.post('/forest/apimaps', api_map.to_json)
      rescue Faraday::Error => e
        status = e.response[:status] if e.response
        if status
          ForestAdminAgent::Facades::Container.logger.log(
            'Error',
            "Failed to send schema: invalid request (HTTP #{status})"
          )
        else
          ForestAdminAgent::Facades::Container.logger.log(
            'Error',
            'Failed to send schema: cannot reach ForestAdmin server'
          )
        end
      end
    end
  end
end
