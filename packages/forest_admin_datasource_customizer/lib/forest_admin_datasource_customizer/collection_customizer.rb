module ForestAdminDatasourceCustomizer
  class CollectionCustomizer
    attr_reader :datasource_customizer, :stack, :name

    def initialize(datasource_customizer, stack, name)
      @datasource_customizer = datasource_customizer
      @stack = stack
      @name = name
    end

    def add_action(name, definition)
      push_customization(
        proc { @stack.action.get_collection(@name).add_action(name, definition) }
      )
    end

    def schema
      @stack.datasource.get_collection(@name).schema
    end

    def collection
      @stack.datasource.get_collection(@name)
    end

    def use(plugin, options = [])
      push_customization(
        proc { plugin.run(@datasource_customizer, self, options) }
      )
    end

    def disable_count
      push_customization(
        -> { @stack.schema.get_collection(@name).override_schema(countable: false) }
      )
    end

    def replace_search(definition)
      push_customization(
        proc { @stack.search.get_collection(@name).replace_search(definition) }
      )
    end

    def push_customization(customization)
      @stack.queue_customization(customization)
    end
  end
end
