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

    def add_field(name, definition)
      push_customization(
        proc {
          collection_before_relations = @stack.early_computed.get_collection(@name)
          collection_after_relations = @stack.late_computed.get_collection(@name)
          can_be_computed_before_relations = definition.dependencies.all? do |field|
            !ForestAdminDatasourceToolkit::Utils::Collection.get_field_schema(collection_before_relations, field).nil?
          rescue StandardError
            false
          end

          collection = can_be_computed_before_relations ? collection_before_relations : collection_after_relations

          collection.register_computed(name, definition)
        }
      )
    end

    private

    def push_customization(customization)
      @stack.queue_customization(customization)
    end
  end
end
