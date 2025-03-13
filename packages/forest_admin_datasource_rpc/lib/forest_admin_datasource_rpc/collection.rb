module ForestAdminDatasourceRpc
  class Collection < ForestAdminDatasourceToolkit::Collection
    def initialize(datasource, name, options, schema)
      super(datasource, name)
      @options = options
      @rpc_collection_uri = "#{options["uri"]}/forest/rpc/#{name}"

      ForestAdminAgent::Facades::Container.logger.log('Debug', "Create Rpc collection #{name}.")

      enable_count if schema[:countable]
      enable_search if schema[:searchable]

      schema[:actions].each { |action_name, action_schema| add_action(action_name, action_schema) }
      schema[:charts].each { |chart| add_chart(chart) }
      schema[:fields].each { |field_name, field_schema| add_field(field_name, field_schema) }
      add_segments(schema[:segments])
    end

    def list(caller, filter, projection)
      # TODO
    end

    def create(caller, data)
      # TODO
    end

    def update(caller, filter, data)
      # TODO
    end

    def delete(caller, filter)
      # TODO
    end

    def aggregate(caller, filter, aggregation, limit = nil)
      # TODO
    end

    def execute(caller, name, data, filter = nil)
      # TODO
    end

    def get_form(caller, name, data = nil, filter = nil, metas = nil)
      # TODO
    end

    def render_chart(_caller, name, _record_id)
      # TODO
    end
  end
end
