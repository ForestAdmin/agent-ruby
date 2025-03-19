module ForestAdminDatasourceRpc
  class Collection < ForestAdminDatasourceToolkit::Collection
    include ForestAdminDatasourceRpc::Utils

    def initialize(datasource, name, options, schema)
      super(datasource, name)
      @options = options
      @client = RpcClient.new(@options[:uri], ForestAdminAgent::Facades::Container.cache(:auth_secret))
      @rpc_collection_uri = "/forest/rpc/#{name}"

      ForestAdminAgent::Facades::Container.logger.log('Debug', "Create Rpc collection #{name}.")

      enable_count if schema[:countable]
      enable_search if schema[:searchable]
      schema[:actions].each { |action_name, action_schema| add_action(action_name, action_schema) }
      # schema[:charts].each { |chart| add_chart(chart) }
      add_fields(schema[:fields])
      add_segments(schema[:segments])
    end

    def add_fields(fields)
      fields.each do |field_name, schema|
        field_name = field_name.to_s
        type = schema[:type]
        schema.delete(:type)
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
      params = { collection_name: name, caller: caller.to_h, filter: filter.to_h, projection: projection,
                 timezone: caller.timezone }
      url = "#{@rpc_collection_uri}/list"

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' list call to the Rpc agent on #{url}."
      )

      @client.call_rpc(url, method: :get, payload: params)
    end

    def create(caller, data)
      params = { caller: caller.to_h, timezone: caller.timezone, data: data }
      url = '/create'

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' creation call to the Rpc agent on #{url}."
      )

      # response = @client.post(url, params)
      response = @client.call_rpc(url, method: :post, payload: params)
      response.body
    end

    def update(caller, filter, data)
      params = { caller: caller.to_h, timezone: caller.timezone, filter: filter, data: data }
      url = '/update'

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' update call to the Rpc agent on #{url}."
      )

      # @client.put(url, params)
      @client.call_rpc(url, method: :post, payload: params)
    end

    def delete(caller, filter)
      params = { caller: caller.to_h, timezone: caller.timezone, filter: filter }
      url = '/delete'

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' delete call to the Rpc agent on #{url}."
      )

      # @client.delete(url, params)
      @client.call_rpc(url, method: :delete, payload: params)
    end

    def aggregate(caller, filter, aggregation, limit = nil)
      params = { caller: caller.to_h, timezone: caller.timezone, filter: filter, aggregation: aggregation,
                 limit: limit }
      url = '/aggregate'

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' aggregation call to the Rpc agent on #{url}."
      )

      # response = @client.get(url, params)
      response = @client.call_rpc(url, method: :get, payload: params)
      response.body
    end

    def execute(caller, name, _data, filter = nil)
      params = { caller: caller.to_h, timezone: caller.timezone, filter: filter, name: name }
      url = '/action-execute'

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' action #{name} call to the Rpc agent on #{url}."
      )

      # response = @client.post(url, params)
      response = @client.call_rpc(url, method: :post, payload: params)
      # TODO: action with file
      response.body
    end

    def get_form(caller, name, data = nil, filter = nil, metas = nil)
      params = { caller: caller.to_h, timezone: caller.timezone, filter: filter, name: name, metas: metas, data: data }
      url = '/action-form'

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' action form #{name} call to the Rpc agent on #{url}."
      )

      # response = @client.post(url, params)
      response = @client.call_rpc(url, method: :post, payload: params)
      response.body
    end

    def render_chart(caller, name, record_id)
      params = { caller: caller.to_h, timezone: caller.timezone, name: name, record_id: record_id }
      url = '/chart'

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' chart #{name} call to the Rpc agent on #{url}."
      )

      # response = @client.get(url, params)
      response = @client.call_rpc(url, method: :get, payload: params)
      response.body
    end
  end
end
