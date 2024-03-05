module Factory
  def datasource_with_collections_build(collections)
    datasource = ForestAdminDatasourceToolkit::Datasource.new
    collections.each do |collection|
      allow(collection).to receive(:datasource).and_return(datasource)
      datasource.add_collection(collection)
    end

    datasource
  end

  def collection_build(args)
    instance_double(
      ForestAdminDatasourceToolkit::Collection,
      {
        # nativeDriver: null,
        datasource: ForestAdminDatasourceToolkit::Datasource.new,
        name: 'collection',
        schema: {}, # collectionSchemaFactory.build(),
        execute: nil,
        get_form: nil,
        render_chart: nil,
        create: nil,
        list: nil,
        update: nil,
        delete: nil,
        aggregate: nil
      }.merge(args)
    )
  end
end
