module ForestAdminDatasourceRpc
  class Collection < ForestAdminDatasourceToolkit::Collection
    def initialize(datasource, name, options, schema)
      super(datasource, name)
      @options = options
      @rpc_collection_uri = "#{options[:uri]}/forest/rpc/#{name}"
      @client = Utils::ApiRequester.new(@rpc_collection_uri, @options[:token])

      ForestAdminAgent::Facades::Container.logger.log('Debug', "Create Rpc collection #{name}.")

      enable_count if schema[:countable]
      enable_search if schema[:searchable]

      schema[:actions].each { |action_name, action_schema| add_action(action_name, action_schema) }
      # schema[:charts].each { |chart| add_chart(chart) }
      schema[:fields].each { |field_name, field_schema| add_field(field_name, field_schema) }
      add_segments(schema[:segments])
    end

    def list(caller, filter, projection)
      params = { caller: caller.to_h, filter: filter.to_h, projection: projection, timezone: caller.timezone }
      # url = "/list?#{URI.encode_www_form(params)}"
      url = '/list'

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' list call to the Rpc agent on #{url}."
      )

      response = @client.get(url, params)
      response.body
    end

    def create(caller, data)
      params = { caller: caller.to_h, timezone: caller.timezone, data: data }
      url = '/create'

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' creation call to the Rpc agent on #{url}."
      )

      response = @client.post(url, params)
      response.body
    end

    def update(caller, filter, data)
      params = { caller: caller.to_h, timezone: caller.timezone, filter: filter, data: data }
      url = '/update'

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' update call to the Rpc agent on #{url}."
      )

      @client.put(url, params)
    end

    def delete(caller, filter)
      params = { caller: caller.to_h, timezone: caller.timezone, filter: filter }
      url = '/delete'

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' delete call to the Rpc agent on #{url}."
      )

      @client.delete(url, params)
    end

    def aggregate(caller, filter, aggregation, limit = nil)
      params = { caller: caller.to_h, timezone: caller.timezone, filter: filter, aggregation: aggregation,
                 limit: limit }
      url = '/aggregate'

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' aggregation call to the Rpc agent on #{url}."
      )

      response = @client.get(url, params)
      response.body
    end

    def execute(caller, name, _data, filter = nil)
      params = { caller: caller.to_h, timezone: caller.timezone, filter: filter, name: name }
      url = '/action-execute'

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' action #{name} call to the Rpc agent on #{url}."
      )

      response = @client.post(url, params)
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

      response = @client.post(url, params)
      response.body
    end

    def render_chart(caller, name, record_id)
      params = { caller: caller.to_h, timezone: caller.timezone, name: name, record_id: record_id }
      url = '/chart'

      ForestAdminAgent::Facades::Container.logger.log(
        'Debug',
        "Forwarding '#{@name}' chart #{name} call to the Rpc agent on #{url}."
      )

      response = @client.get(url, params)
      response.body
    end
  end
end
