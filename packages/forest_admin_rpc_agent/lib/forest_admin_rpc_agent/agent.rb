require 'digest'
require 'fileutils'

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

      build_and_cache_schema_from_datasource
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

    def load_and_cache_schema_from_file(_schema_path)
      # File exists but RPC schema needs internal format - build from datasource
      # The file is kept for reference/frontend but RPC always uses internal format
      datasource = @container.resolve(:datasource)
      @cached_schema = build_rpc_schema_from_datasource(datasource)
      compute_and_cache_hash
    end

    def generate_and_cache_schema(schema_path)
      datasource = @container.resolve(:datasource)

      # Generate frontend schema for file (used by Forest Admin)
      generated = ForestAdminAgent::Utils::Schema::SchemaEmitter.generate(datasource)
      meta = ForestAdminAgent::Utils::Schema::SchemaEmitter.meta

      schema = {
        meta: meta,
        collections: generated
      }

      FileUtils.mkdir_p(File.dirname(schema_path))
      File.write(schema_path, format_schema_json(schema))

      # Build RPC schema in internal format (used by master agent)
      @cached_schema = build_rpc_schema_from_datasource(datasource)
      compute_and_cache_hash
    end

    def build_and_cache_schema_from_datasource
      datasource = @container.resolve(:datasource)

      @cached_schema = build_rpc_schema_from_datasource(datasource)
      compute_and_cache_hash
    end

    def build_rpc_schema_from_datasource(datasource)
      schema = customizer.schema

      # Serialize collections with internal schema format (fields as hash with :type keys)
      collections = datasource.collections.map { |_name, collection| serialize_collection_for_rpc(collection) }
      schema[:collections] = collections.sort_by { |c| c[:name] }

      connections = datasource.live_query_connections.keys.map { |connection_name| { name: connection_name } }
      schema[:native_query_connections] = connections

      schema
    end

    def serialize_collection_for_rpc(collection)
      {
        name: collection.name,
        countable: collection.schema[:countable],
        searchable: collection.schema[:searchable],
        segments: collection.schema[:segments] || [],
        charts: collection.schema[:charts] || [],
        actions: serialize_actions_for_rpc(collection.schema[:actions] || {}),
        fields: serialize_fields_for_rpc(collection.schema[:fields] || {})
      }
    end

    def serialize_fields_for_rpc(fields)
      fields.transform_values do |field_schema|
        serialize_field_schema(field_schema)
      end
    end

    def serialize_field_schema(field_schema)
      case field_schema
      when ForestAdminDatasourceToolkit::Schema::ColumnSchema
        {
          type: 'Column',
          column_type: field_schema.column_type,
          filter_operators: field_schema.filter_operators,
          is_primary_key: field_schema.is_primary_key,
          is_read_only: field_schema.is_read_only,
          is_sortable: field_schema.is_sortable,
          default_value: field_schema.default_value,
          enum_values: field_schema.enum_values,
          validation: field_schema.validation
        }
      when ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema
        {
          type: 'ManyToOne',
          foreign_collection: field_schema.foreign_collection,
          foreign_key: field_schema.foreign_key,
          foreign_key_target: field_schema.foreign_key_target
        }
      when ForestAdminDatasourceToolkit::Schema::Relations::OneToOneSchema
        {
          type: 'OneToOne',
          foreign_collection: field_schema.foreign_collection,
          origin_key: field_schema.origin_key,
          origin_key_target: field_schema.origin_key_target
        }
      when ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema
        {
          type: 'OneToMany',
          foreign_collection: field_schema.foreign_collection,
          origin_key: field_schema.origin_key,
          origin_key_target: field_schema.origin_key_target
        }
      when ForestAdminDatasourceToolkit::Schema::Relations::ManyToManySchema
        {
          type: 'ManyToMany',
          foreign_collection: field_schema.foreign_collection,
          foreign_key: field_schema.foreign_key,
          foreign_key_target: field_schema.foreign_key_target,
          origin_key: field_schema.origin_key,
          origin_key_target: field_schema.origin_key_target,
          through_collection: field_schema.through_collection
        }
      when ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicManyToOneSchema
        {
          type: 'PolymorphicManyToOne',
          foreign_collections: field_schema.foreign_collections,
          foreign_key: field_schema.foreign_key,
          foreign_key_type_field: field_schema.foreign_key_type_field,
          foreign_key_targets: field_schema.foreign_key_targets
        }
      when ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicOneToOneSchema
        {
          type: 'PolymorphicOneToOne',
          foreign_collection: field_schema.foreign_collection,
          origin_key: field_schema.origin_key,
          origin_key_target: field_schema.origin_key_target,
          origin_type_field: field_schema.origin_type_field,
          origin_type_value: field_schema.origin_type_value
        }
      when ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicOneToManySchema
        {
          type: 'PolymorphicOneToMany',
          foreign_collection: field_schema.foreign_collection,
          origin_key: field_schema.origin_key,
          origin_key_target: field_schema.origin_key_target,
          origin_type_field: field_schema.origin_type_field,
          origin_type_value: field_schema.origin_type_value
        }
      else
        # Fallback: try to convert to hash if possible
        field_schema.respond_to?(:to_h) ? field_schema.to_h : field_schema
      end
    end

    def serialize_actions_for_rpc(actions)
      actions.transform_values do |action|
        action.respond_to?(:to_h) ? action.to_h : action
      end
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
