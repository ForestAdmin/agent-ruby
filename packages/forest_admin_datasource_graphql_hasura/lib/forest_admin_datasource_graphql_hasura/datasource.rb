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

      mark_groupable_foreign_keys

      ForestAdminDatasourceGraphqlHasura.logger.info(
        "[forest_admin_datasource_graphql_hasura] #{tables.size} collections registered " \
        "(#{tables.sum { |table| table.polymorphics.size }} polymorphic relations detected)."
      )
    end

    # The capabilities route publishes is_groupable, and grouping goes through the
    # parent's nested `<relation>_aggregate`, which only exists when Hasura
    # declares the reverse array relationship: marking a foreign key without one
    # would have the UI offer a group-by that the aggregator then rejects.
    def mark_groupable_foreign_keys
      collections.each_value do |collection|
        collection.schema[:fields].each_value do |field|
          next unless field.type == 'ManyToOne' && reverse_declared?(collection, field)

          foreign_key = collection.schema[:fields][field.foreign_key]
          foreign_key.is_groupable = true if foreign_key.respond_to?(:is_groupable=)
        end
      end
    end

    def reverse_declared?(collection, relation)
      parent = get_collection(relation.foreign_collection)

      parent.schema[:fields].each_value.any? do |field|
        field.type == 'OneToMany' &&
          field.foreign_collection == collection.name &&
          field.origin_key == relation.foreign_key
      end
    end
  end
end
