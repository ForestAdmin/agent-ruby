module ForestAdminDatasourceCustomizer
  module Decorators
    module Write
      class WriteDatasourceDecorator < ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator
        def initialize(child_datasource)
          create = new DataSourceDecorator(child_datasource, CreateRelations::CreateRelationsCollectionDecorator)
          update = new DataSourceDecorator(create, UpdateRelations::UpdateRelationsCollectionDecorator)
          super(update, WriteReplace::WriteReplaceCollectionDecorator)
        end
      end
    end
  end
end
