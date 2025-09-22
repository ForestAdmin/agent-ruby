module ForestAdminTestToolkit
  module Factory
    module Datasource
      def build_datasource_with_collections(collections)
        datasource = ForestAdminDatasourceToolkit::Datasource.new
        collections.each do |collection|
          allow(collection).to receive(:datasource).and_return(datasource)
          datasource.add_collection(collection)
        end

        datasource
      end

      def build_datasource(args = {})
        instance_double(
          ForestAdminDatasourceToolkit::Datasource,
          {
            schema: { charts: [] },
            collections: [],
            get_collection: nil,
            add_collection: nil,
            render_chart: nil,
            **args
          }
        )
      end
    end
  end
end
