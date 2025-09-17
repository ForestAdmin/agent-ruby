module ForestAdminDatasourceCustomizer
  module Decorators
    module Search
      class SearchDatasourceDecorator < ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator
        def initialize(child_datasource)
          super(child_datasource, SearchCollectionDecorator)
        end

        def add_replacer(definition)
          collections.each_value do |collection|
            collection.replace_search(definition)
          end
        end
      end
    end
  end
end
