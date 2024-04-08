module Factory
  def datasource_build(args = {})
    instance_double(
      ForestAdminDatasourceToolkit::Datasource,
      {
        schema: { charts: [] },
        collections: {},
        get_collection: nil,
        add_collection: nil,
        render_chart: nil,
        **args
      }
    )
  end

  def datasource_with_collections_build(collections)
    datasource = ForestAdminDatasourceToolkit::Datasource.new
    collections.each do |collection|
      allow(collection).to receive(:datasource).and_return(datasource)
      datasource.add_collection(collection)
    end

    datasource
  end

  def collection_build(args = {})
    instance_double(
      ForestAdminDatasourceToolkit::Collection,
      {
        datasource: ForestAdminDatasourceToolkit::Datasource.new,
        name: 'collection',
        schema: {
          charts: [],
          fields: {},
          countable: false,
          searchable: false
        }.merge(args[:schema]),
        execute: nil,
        get_form: nil,
        render_chart: nil,
        create: nil,
        list: nil,
        update: nil,
        delete: nil,
        aggregate: nil,
        **args.except!(:schema)
      }
    )
  end
end
