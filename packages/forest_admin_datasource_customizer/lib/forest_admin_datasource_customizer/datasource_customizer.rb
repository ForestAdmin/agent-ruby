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
      @stack.datasource.collections.transform_values { |collection| get_collection(collection.name) }
    end

    def datasource(logger)
      @stack.apply_queued_customizations(logger)

      @stack.datasource
    end

    def add_datasource(datasource, options)
      @stack.queue_customization(lambda {
        # TODO: add call logger

        if options[:include] || options[:exclude]
          publication_decorator = Decorators::Publication::PublicationDatasourceDecorator.new(datasource)
          publication_decorator.keep_collections_matching(options[:include], options[:exclude])
          datasource = publication_decorator
        end

        # TODO: add rename behavior

        @composite_datasource.add_datasource(datasource)
      })

      self
    end

    def add_chart(name, definition)
      # TODO: to implement
    end

    def use(plugin, options)
      # TODO: to implement
    end

    def customize_collection(name, handle)
      handle.call(get_collection(name))
    end

    # removeCollection(...names: TCollectionName<S>[]): this {
    #     this.stack.queueCustomization(async () => {
    #       this.stack.publication.keepCollectionsMatching(undefined, names);
    #     });
    #
    #     return this;
    #   }

    def remove_collection(*names)
      @stack.queue_customization(-> { @stack.publication.keep_collections_matching(nil, names) })

      self
    end
  end
end
