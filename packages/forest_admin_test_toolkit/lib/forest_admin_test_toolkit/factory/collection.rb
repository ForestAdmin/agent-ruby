module ForestAdminTestToolkit
  module Factory
    module Collection
      def build_collection(args = {})
        instance_double(
          ForestAdminDatasourceToolkit::Collection,
          {
            datasource: ForestAdminDatasourceToolkit::Datasource.new,
            name: 'collection',
            schema: {
              actions: {},
              charts: [],
              fields: {},
              countable: false,
              searchable: false,
              segments: []
            }.merge(args[:schema] || {}),
            execute: nil,
            get_form: nil,
            render_chart: nil,
            create: nil,
            list: nil,
            update: nil,
            delete: nil,
            aggregate: nil,
            **args.except(:schema)
          }
        )
      end
    end
  end
end
