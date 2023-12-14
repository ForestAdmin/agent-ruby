module ForestAdminDatasourceCustomizer
  class CollectionCustomizer
    attr_reader :datasource_customizer, :stack, :name

    def initialize(datasource_customizer, stack, name)
      @datasource_customizer = datasource_customizer
      @stack = stack
      @name = name
    end

    def schema
      @stack.datasource.collection(@name).schema
    end

    def collection
      @stack.datasource.collection(@name)
    end

    def use(plugin, options = [])
      push_customization(
        -> { plugin.run(@datasource_customizer, self, options) }
      )
    end
  end
end
