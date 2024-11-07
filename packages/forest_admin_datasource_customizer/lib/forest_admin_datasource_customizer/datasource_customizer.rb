module ForestAdminDatasourceCustomizer
  class DatasourceCustomizer
    attr_reader :stack, :datasources

    def initialize(_db_config = {})
      @composite_datasource = ForestAdminDatasourceToolkit::Datasource.new
      @stack = Decorators::DecoratorsStack.new(@composite_datasource)
      @datasources = []
    end

    def schema
      @stack.validation.schema
    end

    def get_collection(name)
      CollectionCustomizer.new(self, @stack, name)
    end

    def collections
      @stack.datasource.collections.transform_values { |collection| get_collection(collection.name) }
    end

    def datasource(logger)
      @stack.apply_queued_customizations(logger)

      @stack.datasource
    end

    def add_datasource(datasource, options)
      @stack.queue_customization(lambda {
        if options[:include] || options[:exclude]
          publication_decorator = Decorators::Publication::PublicationDatasourceDecorator.new(datasource)
          publication_decorator.keep_collections_matching(options[:include], options[:exclude])
          datasource = publication_decorator
        end

        if options[:rename]
          rename_collection_decorator = Decorators::RenameCollection::RenameCollectionDatasourceDecorator.new(
            datasource
          )
          rename_collection_decorator.rename_collections(options[:rename])
          datasource = rename_collection_decorator
        end

        datasource.collections.each_value do |collection|
          @composite_datasource.add_collection(collection)
        end
      })

      datasource_name = datasource.name
      counter = 1

      counter += 1 while @datasources.any? { |ds| ds.name == "#{datasource_name}_#{counter}" }

      datasource.name = "#{datasource_name}_#{counter}"
      @datasources << datasource

      self
    end

    # Create a new API chart
    # @param name name of the chart
    # @param definition definition of the chart
    # @example
    # .addChart('num_customers') { |context, result_builder| result_builder.value(123) }
    def add_chart(name, &definition)
      push_customization { @stack.chart.add_chart(name, &definition) }
    end

    def use(plugin, options)
      push_customization { plugin.new.run(self, nil, options) }
    end

    def customize_collection(name, handle)
      handle.call(get_collection(name))
    end

    def remove_collection(*names)
      @stack.queue_customization(-> { @stack.publication.keep_collections_matching(nil, names) })

      self
    end

    private

    def push_customization(&customization)
      @stack.queue_customization(customization)
    end
  end
end
