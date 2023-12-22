module ForestAdminDatasourceCustomizer
  class CollectionCustomizer
    attr_reader :datasource_customizer, :stack, :name

    def initialize(datasource_customizer, stack, name)
      @datasource_customizer = datasource_customizer
      @stack = stack
      @name = name
    end

    def schema
      @stack.datasource.get_collection(@name).schema
    end

    def collection
      @stack.datasource.get_collection(@name)
    end

    def use(plugin, options = [])
      push_customization(
        -> { plugin.run(@datasource_customizer, self, options) }
      )
    end

    def disable_count
      push_customization(
        -> { @stack.schema.get_collection(@name).override_schema(countable: false) }
      )
    end

    def replace_search(definition)
      push_customization(
        -> { @stack.search.get_collection(@name).replace_search(definition) }
      )
    end
  end
end
