module ForestAdminDatasourceToolkit
  class Collection < Components::Contracts::CollectionContract
    attr_accessor :fields, :segments

    attr_reader :actions,
                :charts,
                :datasource,
                :name,
                :schema,
                :native_driver

    attr_writer :searchable,
                :countable

    @schema = {}
    @fields = {}
    @actions = {}
    @segments = {}
    @charts = {}
    @searchable = false
    @countable = false

    def initialize(
      datasource,
      name,
      native_driver = nil
    )
      super
      @datasource = datasource
      @name = name
      @native_driver = native_driver
    end

    def is_countable?
      @countable
    end

    def is_searchable?
      @searchable
    end

    def add_field(name, field)
      raise Exceptions::ForestException, "Field #{name} already defined in collection" if @fields.key? name

      @fields[name] = field
    end

    def add_fields(fields)
      fields.each do |name, field|
        add_field(name, field)
      end
    end
  end
end
