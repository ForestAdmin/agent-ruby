module ForestAdminDatasourceToolkit
  class Datasource < Components::Contracts::DatasourceContract
    attr_reader :collections, :schema, :live_query_connections

    def initialize
      super
      @schema = { charts: [] }
      @collections = {}
      @live_query_connections = {}
    end

    def get_collection(name)
      unless @collections.key? name
        raise ForestAdminAgent::Http::Exceptions::NotFoundError, "Collection #{name} not found."
      end

      @collections[name]
    end

    def add_collection(collection)
      if @collections.key? collection.name
        raise ForestAdminAgent::Http::Exceptions::ConflictError,
              "Collection #{collection.name} already defined in datasource"
      end

      @collections[collection.name] = collection
    end

    def render_chart(_caller, name)
      raise ForestAdminAgent::Http::Exceptions::NotFoundError, "No chart named #{name} exists on this datasource."
    end

    def execute_native_query(_connection_name, _query, _binds)
      raise ForestAdminAgent::Http::Exceptions::UnprocessableError, 'this datasource do not support native query.'
    end

    def build_binding_symbol(_connection_name, _binds)
      raise ForestAdminAgent::Http::Exceptions::UnprocessableError, 'this datasource do not support native query.'
    end

    def add_chart(chart)
      if @schema[:charts].any? do |c|
        c[:name] == chart[:name]
      end
        raise ForestAdminAgent::Http::Exceptions::ConflictError, "Chart #{chart[:name]} already defined in datasource"
      end

      @schema[:charts] << chart
    end
  end
end
