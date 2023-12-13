require 'active_record'

module ForestAdminDatasourceCustomizer
  class DatasourceCustomizer
    attr_reader :stack

    def initialize(_db_config = {})
      @composite_datasource = ForestAdminDatasourceToolkit::Datasource.new
      @stack = Decorators::DecoratorsStack.new(@composite_datasource)
    end

    def add_datasource(datasource, options)
      # TODO: to implement
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

    def collection(name)
      # TODO: to implement
    end

    def collections
      # TODO: to implement
    end

    def datasource
      # TODO: to implement
    end
  end
end
