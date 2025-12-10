require 'digest'
require 'fileutils'

module ForestAdminRpcAgent
  class Agent < ForestAdminAgent::Builder::AgentFactory
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
        return
      end

      datasource = @container.resolve(:datasource)

      # Write schema file for reference (only in development mode)
      write_schema_file_for_reference(datasource) unless ForestAdminRpcAgent::Facades::Container.cache(:is_production)

      # Build and cache RPC schema from live datasource
      @cached_schema = build_rpc_schema_from_datasource(datasource)
      compute_and_cache_hash

      ForestAdminRpcAgent::Facades::Container.logger.log(
        'Info',
        'RPC agent schema computed from datasource and cached.'
      )
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

      build_and_cache_rpc_schema_from_datasource
      @cached_schema
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
    end

    def write_schema_file_for_reference(datasource)
      schema_path = ForestAdminRpcAgent::Facades::Container.cache(:schema_path)
      schema = build_schema(datasource)
      FileUtils.mkdir_p(File.dirname(schema_path))
      write_schema_file(schema_path, schema)

      ForestAdminRpcAgent::Facades::Container.logger.log(
        'Info',
        "RPC agent schema file saved to #{schema_path}"
      )
    end

    def build_and_cache_rpc_schema_from_datasource
      datasource = @container.resolve(:datasource)

      @cached_schema = build_rpc_schema_from_datasource(datasource)
      compute_and_cache_hash
    end

    def build_rpc_schema_from_datasource(datasource)
      schema = customizer.schema

      schema[:collections] = datasource.collections
                                       .map { |_name, collection| collection.schema.merge({ name: collection.name }) }
                                       .sort_by { |c| c[:name] }

      schema[:native_query_connections] = datasource.live_query_connections.keys
                                                    .map { |connection_name| { name: connection_name } }

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
