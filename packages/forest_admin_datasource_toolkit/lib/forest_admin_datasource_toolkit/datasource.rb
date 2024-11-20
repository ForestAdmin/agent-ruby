module ForestAdminDatasourceToolkit
  class Datasource < Components::Contracts::DatasourceContract
    attr_reader :collections, :schema
    attr_accessor :name

    def initialize
      super
      @schema = { charts: [] }
      @collections = {}
      @name = nil
    end

    def get_collection(name)
      raise Exceptions::ForestException, "Collection #{name} not found." unless @collections.key? name

      @collections[name]
    end

    def add_collection(collection)
      if @collections.key? collection.name
        raise Exceptions::ForestException, "Collection #{collection.name} already defined in datasource"
      end

      @collections[collection.name] = collection
    end

    def render_chart(_caller, name)
      raise Exceptions::ForestException, "No chart named #{name} exists on this datasource."
    end

    def execute_native_query(_connection_name, _query)
      raise Exceptions::ForestException, 'this datasource do not support native query.'
    end
  end
end
