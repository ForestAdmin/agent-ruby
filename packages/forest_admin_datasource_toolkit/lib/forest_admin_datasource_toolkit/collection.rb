module ForestAdminDatasourceToolkit
  class Collection < Components::Contracts::CollectionContract
    attr_accessor :segments

    attr_reader :actions,
                :charts,
                :datasource,
                :name,
                :schema,
                :native_driver

    def initialize(datasource, name, native_driver: nil)
      super()
      @datasource = datasource
      @name = name
      @native_driver = native_driver
      @schema = {
        fields: {},
        countable: false,
        searchable: false
      }
      @actions = {}
      @segments = {}
      @charts = {}
    end

    def enable_count
      schema[:countable] = true
    end

    def is_countable?
      schema[:countable]
    end

    def is_searchable?
      schema[:searchable]
    end

    def fields
      schema[:fields]
    end

    def add_field(name, field)
      raise Exceptions::ForestException, "Field #{name} already defined in collection" if @schema[:fields].key?(name)

      schema[:fields][name] = field
    end

    def add_fields(fields)
      fields.each do |name, field|
        add_field(name, field)
      end
    end

    def add_action(name, action)
      raise Exceptions::ForestException, "Action #{name} already defined in collection" if @actions[key]

      @actions[name] = action
    end
  end
end
