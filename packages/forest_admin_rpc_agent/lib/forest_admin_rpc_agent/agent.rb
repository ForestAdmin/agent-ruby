require 'digest'
require 'fileutils'

module ForestAdminRpcAgent
  class Agent < ForestAdminAgent::Builder::AgentFactory
    include ForestAdminAgent::Http::Exceptions

    attr_reader :rpc_collections, :cached_schema

    def setup(options)
      super
      @rpc_collections = []
      @cached_schema = nil
      @customizer = ForestAdminRpcAgent::DatasourceCustomizer.new
    end

    def add_datasource(datasource, options = {})
      if options[:mark_collections_as_rpc]
        options[:mark_collections_callback] = ->(ds) { mark_collections_as_rpc(*ds.collections.keys) }
      end

      super
    end

    def send_schema(force: false)
      if should_skip_schema_update? && !force
        log_schema_skip
        return
      end

      datasource = @container.resolve(:datasource)

      @cached_schema = build_rpc_schema_from_datasource(datasource)

      # Write schema file for reference (only in development mode)
      # Uses the same serialization as the /rpc-schema route
      write_schema_file_for_reference unless ForestAdminRpcAgent::Facades::Container.cache(:is_production)

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

    private

    def should_skip_schema_update?
      ForestAdminRpcAgent::Facades::Container.cache(:skip_schema_update) == true
    end

    def log_schema_skip
      logger = ForestAdminRpcAgent::Facades::Container.logger
      logger.log('Warn', '[ForestAdmin] Schema update skipped (skip_schema_update flag is true)')
    end

    def write_schema_file_for_reference
      schema_path = ForestAdminRpcAgent::Facades::Container.cache(:schema_path)
      FileUtils.mkdir_p(File.dirname(schema_path))
      # Use the same serialization as the /rpc-schema route (.to_json)
      File.write(schema_path, JSON.pretty_generate(JSON.parse(@cached_schema.to_json)))

      ForestAdminRpcAgent::Facades::Container.logger.log(
        'Info',
        "RPC agent schema file saved to #{schema_path}"
      )
    end

    def build_rpc_schema_from_datasource(datasource)
      schema = customizer.schema

      rpc_relations = {}
      collections = []

      datasource.collections.each_value do |collection|
        relations = {}

        if @rpc_collections.include?(collection.name)
          extract_rpc_collection_relations(collection, relations)
        else
          collections << build_normal_collection_payload(collection, relations)
        end

        rpc_relations[collection.name] = relations unless relations.empty?
      end

      schema[:collections] = collections.sort_by { |c| c[:name] }
      schema[:rpc_relations] = rpc_relations

      schema[:native_query_connections] = datasource.live_query_connections.keys
                                                    .map { |connection_name| { name: connection_name } }

      schema[:etag] = Digest::SHA1.hexdigest(schema.to_json)

      ForestAdminRpcAgent::Facades::Container.logger.log(
        'Debug',
        "RPC agent schema etag computed: #{schema[:etag]}"
      )

      schema
    end

    # RPC collection → extract relations targeting non-RPC collections.
    def extract_rpc_collection_relations(collection, relations)
      collection.schema[:fields].each do |field_name, field|
        next if field.type == 'Column'
        next if relation_targets_rpc_collection?(field)

        relations[field_name] = field
      end
    end

    # Normal (non-RPC) collection → split fields between local schema and cross-RPC relations.
    def build_normal_collection_payload(collection, relations)
      fields = {}

      collection.schema[:fields].each do |field_name, field|
        if field.type != 'Column' && relation_targets_rpc_collection?(field)
          relations[field_name] = field
        else
          if field.type == 'Column'
            field.filter_operators = ForestAdminAgent::Utils::Schema::FrontendFilterable.sort_operators(
              field.filter_operators
            )
          end
          fields[field_name] = field
        end
      end

      collection.schema.merge(
        name: collection.name,
        fields: fields,
        actions: serialize_actions(collection.schema[:actions])
      )
    end

    # Only expose the fields needed by an RPC consumer: scope, is_generate_file, static_form,
    # description, submit_button_label. Drops `form` (computed via /action-form) and `execute`
    # (server-side callback) — neither belongs on the wire.
    def serialize_actions(actions)
      (actions || {}).transform_values do |action|
        {
          scope: action.scope,
          is_generate_file: action.is_generate_file,
          static_form: action.static_form,
          description: action.description,
          submit_button_label: action.submit_button_label
        }
      end
    end

    def relation_targets_rpc_collection?(relation)
      if relation.type == 'PolymorphicManyToOne'
        relation.foreign_collections.any? { |fc| @rpc_collections.include?(fc) }
      else
        @rpc_collections.include?(relation.foreign_collection)
      end
    end
  end
end
