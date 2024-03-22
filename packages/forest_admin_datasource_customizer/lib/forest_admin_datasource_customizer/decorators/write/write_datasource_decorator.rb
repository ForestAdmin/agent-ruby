module ForestAdminDatasourceCustomizer
  module Decorators
    module Write
      class WriteDatasourceDecorator < ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator
        include ForestAdminDatasourceToolkit::Decorators
        def initialize(child_datasource)
          create = DatasourceDecorator.new(child_datasource, CreateRelations::CreateRelationsCollectionDecorator)
          update = DatasourceDecorator.new(create, UpdateRelations::UpdateRelationsCollectionDecorator)
          super(update, WriteReplace::WriteReplaceCollectionDecorator)
        end
      end
    end
  end
end
