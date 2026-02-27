module ForestAdminDatasourceToolkit
  class Collection < Components::Contracts::CollectionContract
    attr_reader :actions,
                :datasource,
                :name,
                :schema,
                :native_driver

    def initialize(datasource, name, native_driver = nil)
      super()
      @datasource = datasource
      @name = name
      @native_driver = native_driver
      @schema = {
        fields: {},
        countable: false,
        searchable: false,
        charts: [],
        segments: [],
        actions: {},
        aggregation_capabilities: {
          support_groups: true,
          supported_date_operations: %w[Year Quarter Month Week Day]
        }
      }
    end

    def enable_count
      schema[:countable] = true
    end

    def enable_search
      schema[:searchable] = true
    end

    def is_countable?
      schema[:countable]
    end

    def is_searchable?
      schema[:searchable]
    end

    def add_segments(segments)
      schema[:segments] = schema[:segments] | segments
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
      raise Exceptions::ForestException, "Action #{name} already defined in collection" if @schema[:actions].key?(name)

      schema[:actions][name] = action
    end

    def add_chart(name)
      if @schema[:charts].include?(name)
        raise Exceptions::ForestException,
              "Chart #{name} already defined in collection"
      end

      schema[:charts] << name
    end

    def render_chart(_caller, name, _record_id)
      raise Exceptions::ForestException, "Chart #{name} is not implemented."
    end
  end
end
