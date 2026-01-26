module ForestAdminRpcAgent
  class DatasourceCustomizer < ForestAdminDatasourceCustomizer::DatasourceCustomizer
    def add_datasource(datasource, options, mark_collections_as_rpc)
      puts mark_collections_as_rpc
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

        mark_collections_as_rpc&.call(datasource)

        @composite_datasource.add_data_source(datasource)
      })

      self
    end
  end
end
