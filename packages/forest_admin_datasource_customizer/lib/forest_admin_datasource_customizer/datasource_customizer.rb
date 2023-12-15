module ForestAdminDatasourceCustomizer
  class DatasourceCustomizer
    attr_reader :stack

    def initialize(_db_config = {})
      @composite_datasource = ForestAdminDatasourceToolkit::Datasource.new
      @stack = Decorators::DecoratorsStack.new(@composite_datasource)
    end

    def schema
      @stack.datasource.schema
    end

    def get_collection(name)
      CollectionCustomizer.new(self, @stack, name)
    end

    def collections
      @stack.datasource.collections.map { |collection| get_collection(collection.name) }
    end

    def datasource
      # TODO: call @stack.apply_queued_customizations(logger);

      @stack.datasource
    end

    def add_datasource(datasource, _options)
      # TODO: add include/exclude behavior
      # TODO: add rename behavior

      datasource.collections.each_value { |collection| @composite_datasource.add_collection(collection) }
    end

    def add_chart(name, definition)
      # TODO: to implement
    end

    def use(plugin, options)
      # TODO: to implement
    end

    def customize_collection(name, handle)
      # TODO: to implement
    end

    def remove_collection(names)
      # TODO: to implement
    end
  end
end
