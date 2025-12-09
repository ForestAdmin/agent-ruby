require 'digest'

module ForestAdminRpcAgent
  class Agent < ForestAdminAgent::Builder::AgentFactory # rubocop:disable Metrics/ClassLength
    include ForestAdminAgent::Http::Exceptions

    attr_reader :rpc_collections, :cached_schema, :cached_schema_hash

    def setup(options)
      super
      @rpc_collections = []
      @cached_schema = nil
      @cached_schema_hash = nil
    end

    def send_schema(force: false)
      if should_skip_schema_update? && !force
        log_schema_skip
        load_and_cache_schema
        return
      end

      schema_path = ForestAdminRpcAgent::Facades::Container.cache(:schema_path)

      if ForestAdminRpcAgent::Facades::Container.cache(:is_production)
        unless schema_path && File.exist?(schema_path)
          raise InternalServerError.new(
            'Schema file not found in production',
            details: { schema_path: schema_path }
          )
        end

        load_and_cache_schema_from_file(schema_path)

        ForestAdminRpcAgent::Facades::Container.logger.log(
          'Info',
          'RPC agent running in production mode, using existing schema file.'
        )
      else
        generate_and_cache_schema(schema_path)

        ForestAdminRpcAgent::Facades::Container.logger.log(
          'Info',
          "RPC agent schema generated and saved to #{schema_path}"
        )
      end

      ForestAdminRpcAgent::Facades::Container.logger.log(
        'Info',
        'RPC agent does not send schema to Forest Admin servers.'
      )
    end

    def mark_collections_as_rpc(*names)
      @rpc_collections.push(*names)
      self
    end

    # Returns the cached schema for the /rpc-schema route
    # Falls back to building schema from datasource if not cached
    def rpc_schema
      return @cached_schema if @cached_schema

      build_schema_from_datasource
    end

    # Check if provided hash matches the cached schema hash
    def schema_hash_matches?(provided_hash)
      return false unless @cached_schema_hash && provided_hash

      @cached_schema_hash == provided_hash
    end

    private

    def should_skip_schema_update?
      ForestAdminRpcAgent::Facades::Container.cache(:skip_schema_update) == true
    end

    def log_schema_skip
      logger = ForestAdminRpcAgent::Facades::Container.logger
      logger.log('Warn', '[ForestAdmin] Schema update skipped (skip_schema_update flag is true)')
      environment = ForestAdminRpcAgent::Facades::Container.cache(:is_production) ? 'production' : 'development'
      logger.log('Info', "[ForestAdmin] RPC agent running in #{environment} mode")
    end

    def load_and_cache_schema
      schema_path = ForestAdminRpcAgent::Facades::Container.cache(:schema_path)

      if ForestAdminRpcAgent::Facades::Container.cache(:is_production) && schema_path && File.exist?(schema_path)
        load_and_cache_schema_from_file(schema_path)
      else
        # In development with skip_schema_update, still build from datasource
        build_and_cache_schema_from_datasource
      end
    end

    def load_and_cache_schema_from_file(schema_path)
      file_content = JSON.parse(File.read(schema_path), symbolize_names: true)

      @cached_schema = build_rpc_schema_response(file_content[:collections])
      compute_and_cache_hash
    end

    def generate_and_cache_schema(schema_path)
      generated = ForestAdminAgent::Utils::Schema::SchemaEmitter.generate(@container.resolve(:datasource))
      meta = ForestAdminAgent::Utils::Schema::SchemaEmitter.meta

      schema = {
        meta: meta,
        collections: generated
      }

      File.write(schema_path, format_schema_json(schema))

      @cached_schema = build_rpc_schema_response(generated)
      compute_and_cache_hash
    end

    def build_and_cache_schema_from_datasource
      @cached_schema = build_schema_from_datasource
      compute_and_cache_hash
    end

    def build_schema_from_datasource
      schema = customizer.schema
      datasource = customizer.datasource(ForestAdminRpcAgent::Facades::Container.logger)

      schema[:collections] = datasource.collections
                                       .map { |_name, collection| collection.schema.merge({ name: collection.name }) }
                                       .sort_by { |collection| collection[:name] }

      connections = datasource.live_query_connections.keys.map { |connection_name| { name: connection_name } }
      schema[:native_query_connections] = connections

      schema
    end

    def build_rpc_schema_response(collections)
      schema = customizer.schema
      datasource = customizer.datasource(ForestAdminRpcAgent::Facades::Container.logger)

      # Use collections from the schema file but merge with datasource collection schemas
      schema[:collections] = collections.sort_by { |collection| collection[:name] }

      connections = datasource.live_query_connections.keys.map { |connection_name| { name: connection_name } }
      schema[:native_query_connections] = connections

      schema
    end

    def compute_and_cache_hash
      return unless @cached_schema

      @cached_schema_hash = Digest::SHA1.hexdigest(@cached_schema.to_json)

      ForestAdminRpcAgent::Facades::Container.logger.log(
        'Debug',
        "RPC agent schema hash computed: #{@cached_schema_hash}"
      )
    end
  end
end
