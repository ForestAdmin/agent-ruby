require 'base64'

module ForestAdminDatasourceRpc
  class Collection < ForestAdminDatasourceToolkit::Collection
    include ForestAdminDatasourceToolkit::Components
    include ForestAdminDatasourceRpc::Utils
    include ForestAdminDatasourceCustomizer::Decorators::Action

    def initialize(datasource, name, schema)
      super(datasource, name)
      @client = datasource.shared_rpc_client
      @rpc_collection_uri = "/forest/rpc/#{name}"
      @base_params = { collection_name: name }

      ForestAdminAgent::Facades::Container.logger.log('Debug', "Create Rpc collection #{name}.")

      enable_count if schema[:countable]
      enable_search if schema[:searchable]
      add_fields(schema[:fields])
      add_segments(schema[:segments])
      schema[:charts].each { |chart| add_chart(chart) }
      schema[:actions].each do |action_name, action_schema|
        add_action(action_name.to_s, BaseAction.from_plain_object(action_schema))
      end
      @schema[:aggregation_capabilities] = schema[:aggregation_capabilities] if schema[:aggregation_capabilities]
    end

    def add_fields(fields)
      fields.each do |field_name, schema|
        field_name = field_name.to_s
        type = schema[:type]
        schema.delete(:type)
        # remove these
        schema.delete(:allow_null)
        case type
        when 'Column'
          add_field(field_name, ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(**schema))
        when 'ManyToMany'
          add_field(field_name, ForestAdminDatasourceToolkit::Schema::Relations::ManyToManySchema.new(**schema))
        when 'OneToMany'
          add_field(field_name, ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema.new(**schema))
        when 'ManyToOne'
          add_field(field_name, ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema.new(**schema))
        when 'OneToOne'
          add_field(field_name, ForestAdminDatasourceToolkit::Schema::Relations::OneToOneSchema.new(**schema))
        when 'PolymorphicManyToOne'
          add_field(field_name,
                    ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicManyToOneSchema.new(**schema))
        when 'PolymorphicOneToMany'
          add_field(field_name,
                    ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicOneToManySchema.new(**schema))
        when 'PolymorphicOneToOne'
          add_field(field_name,
                    ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicOneToOneSchema.new(**schema))
        end
      end
    end

    def list(caller, filter, projection)
      params = build_params(filter: filter.to_h, projection: projection)
      url = "#{@rpc_collection_uri}/list"

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' list call to the Rpc agent on #{url}."
      )

      @client.call_rpc(url, caller: caller, method: :post, payload: params)
    end

    def create(caller, data)
      params = build_params(data: [data])
      url = "#{@rpc_collection_uri}/create"

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' creation call to the Rpc agent on #{url}."
      )

      res = @client.call_rpc(url, caller: caller, method: :post, payload: params)
      res.first
    end

    def update(caller, filter, data)
      params = build_params(filter: filter.to_h, patch: data)
      url = "#{@rpc_collection_uri}/update"

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' update call to the Rpc agent on #{url}."
      )

      @client.call_rpc(url, caller: caller, method: :post, payload: params)
    end

    def delete(caller, filter)
      params = build_params(filter: filter.to_h)
      url = "#{@rpc_collection_uri}/delete"

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' deletion call to the Rpc agent on #{url}."
      )

      @client.call_rpc(url, caller: caller, method: :post, payload: params)
    end

    def aggregate(caller, filter, aggregation, limit = nil)
      params = build_params(filter: filter.to_h, aggregation: aggregation.to_h, limit: limit)
      url = "#{@rpc_collection_uri}/aggregate"

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' aggregate call to the Rpc agent on #{url}."
      )

      @client.call_rpc(url, caller: caller, method: :post, payload: params)
    end

    def execute(caller, name, data, filter = nil)
      data = encode_form_data(data)
      params = build_params(action: name, filter: filter&.to_h, data: data)
      url = "#{@rpc_collection_uri}/action-execute"

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' action #{name} call to the Rpc agent on #{url}."
      )

      @client.call_rpc(url, caller: caller, method: :post, payload: params)
    end

    def get_form(caller, name, data = nil, filter = nil, metas = nil)
      params = build_params(action: name)
      if caller
        data = encode_form_data(data)
        params = params.merge({ filter: filter&.to_h, metas: metas, data: data })
      end
      url = "#{@rpc_collection_uri}/action-form"

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' action form #{name} call to the Rpc agent on #{url}."
      )

      result = @client.call_rpc(url, caller: caller, method: :post, payload: params, symbolize_keys: true)
      result.map do |field|
        Actions::ActionFieldFactory.build(field.to_h)
      end
    end

    def render_chart(caller, name, record_id)
      params = build_params(chart: name, record_id: record_id)
      url = "#{@rpc_collection_uri}/chart"

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' chart #{name} call to the Rpc agent on #{url}."
      )

      @client.call_rpc(url, caller: caller, method: :post, payload: params)
    end

    private

    def build_params(extra_params = {})
      @base_params.merge(extra_params)
    end

    def encode_form_data(data)
      data.to_h do |key, value|
        if value.is_a?(Hash) && value.key?('buffer')
          [key, "data:#{value["mime_type"]};base64,#{Base64.strict_encode64(value["buffer"])}"]
        else
          [key, value]
        end
      end
    end
  end
end
