module ForestAdminDatasourceCustomizer
  class DatasourceCustomizer
    include DSL::DatasourceHelpers
    attr_reader :stack, :composite_datasource

    def initialize(_db_config = {})
      @composite_datasource = ForestAdminDatasourceCustomizer::CompositeDatasource.new
      @stack = Decorators::DecoratorsStack.new(@composite_datasource)
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
      original_datasource = datasource
      @stack.queue_customization(lambda {
        ds = original_datasource

        if options[:include] || options[:exclude]
          publication_decorator = Decorators::Publication::PublicationDatasourceDecorator.new(ds)
          publication_decorator.keep_collections_matching(options[:include], options[:exclude])
          ds = publication_decorator
        end

        if options[:rename]
          rename_collection_decorator = Decorators::RenameCollection::RenameCollectionDatasourceDecorator.new(ds)
          rename_collection_decorator.rename_collections(options[:rename])
          ds = rename_collection_decorator
        end

        @composite_datasource.add_data_source(ds)
      })

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

    def customize_collection(name)
      yield(get_collection(name))
    end

    def remove_collection(*names)
      @stack.queue_customization(-> { @stack.publication.keep_collections_matching(nil, names) })

      self
    end

    def reload!(logger: nil)
      old_composite = @composite_datasource

      begin
        new_composite = ForestAdminDatasourceCustomizer::CompositeDatasource.new
        @composite_datasource = new_composite
        @stack.reload!(new_composite, logger)
      rescue StandardError => e
        @composite_datasource = old_composite
        raise e
      end

      datasource(logger)
    end

    private

    def push_customization(&customization)
      @stack.queue_customization(customization)
    end
  end
end
