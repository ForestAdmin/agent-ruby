module ForestAdminDatasourceGraphqlHasura
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    attr_reader :client, :configuration

    def initialize(uri:, **options)
      super()

      @configuration = Configuration.new(uri: uri, **options)
      @client = Client.new(@configuration)

      register_collections
    end

    private

    def register_collections
      tables = Introspection::Introspector.new(@client, @configuration).introspect
      converter = Introspection::SchemaConverter.new(tables, @configuration)

      tables.each do |table|
        add_collection(Collection.new(self, table, @client, converter))
      end

      ForestAdminDatasourceGraphqlHasura.logger.info(
        "[forest_admin_datasource_graphql_hasura] #{tables.size} collections registered " \
        "(#{tables.sum { |table| table.polymorphics.size }} polymorphic relations detected)."
      )
    end
  end
end
