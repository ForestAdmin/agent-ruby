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
      tables = deduplicate_collection_names(tables)
      # Detection runs on the surviving tables only, so a polymorphic target
      # can never carry the primary key of a table dedup dropped.
      Introspection::PolymorphismDetector.new(@configuration).detect(tables)
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

    # `user_status` and `user_statuses` both classify to `UserStatus`, and the
    # toolkit refuses a duplicate collection name with an error that names
    # neither table: keep the first (alphabetically, for determinism) and say
    # which tables collided and how to fix it.
    def deduplicate_collection_names(tables)
      converter = Introspection::SchemaConverter.new(tables, @configuration)

      tables.group_by { |table| converter.collection_name_of(table.name) }.flat_map do |name, group|
        next group.first if group.size == 1

        kept, *dropped = group.sort_by(&:name)
        ForestAdminDatasourceGraphqlHasura.logger.warn(
          "[forest_admin_datasource_graphql_hasura] Tables #{group.map(&:name).sort.join(", ")} all map " \
          "to the collection name '#{name}'; only '#{kept.name}' is exposed " \
          "(#{dropped.map(&:name).join(", ")} skipped). Disambiguate with the 'type_values' option."
        )
        kept
      end
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
