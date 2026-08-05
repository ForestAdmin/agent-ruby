module ForestAdminDatasourceGraphqlHasura
  class Collection < ForestAdminDatasourceToolkit::Collection
    ForestException = ForestAdminDatasourceToolkit::Exceptions::ForestException
    Projection = ForestAdminDatasourceToolkit::Components::Query::Projection

    PLACEHOLDER_REFERENCE = { '*' => nil }.freeze

    attr_reader :table_name, :names

    def initialize(datasource, table, client, converter)
      super(datasource, converter.collection_name_of(table.name))

      @table = table
      @table_name = table.name
      # root is the select root field; base (the GraphQL type name) is what
      # generated type names derive from; the operation roots carry their own
      # resolved names, custom or derived. See Query::QueryBuilder.
      @names = { root: table.name, base: table.type_name }.merge(table.root_fields || {})
      @client = client
      @converter = converter

      add_fields(converter.build_fields(table))
      enable_count
      schema[:aggregation_capabilities][:supported_date_operations] = []
    end

    def list(_caller, filter, projection)
      selection = build_selection(projection)
      operation = Query::QueryBuilder.list(@names, filter, selection)
      records = execute(:list, operation)[@names[:root]] || []

      records.map { |record| materialize_polymorphics(record, projection) }
    end

    def create(_caller, data)
      operation = Query::QueryBuilder.create(@names, [writable_columns(data)], column_names)
      returning = execute(:create, operation).dig(@names[:insert], 'returning')

      raise GraphqlError, "No record returned by #{@names[:insert]}" if returning.nil? || returning.empty?

      returning.first
    end

    def update(_caller, filter, data)
      if empty_condition?(filter)
        raise ForestException,
              "Refusing to update every row of '#{name}': the filter carries no condition."
      end

      operation = Query::QueryBuilder.update(@names, filter, writable_columns(data))
      execute(:update, operation)
    end

    def delete(_caller, filter)
      operation = Query::QueryBuilder.delete(@names, filter)
      execute(:delete, operation)
    end

    def aggregate(_caller, filter, aggregation, limit = nil)
      Query::Aggregator.new(self).run(filter, aggregation, limit)
    end

    # Whether a relationship rests on a real foreign key constraint — only the
    # Hasura metadata knows, and only introspection saw it. False when manual
    # or when the metadata was unreachable (constraint unproven).
    def constraint_backed?(relation_name)
      @table.relationships.any? { |rel| rel.name == relation_name && rel.manual == false }
    end

    # Wraps every Hasura call so the failing operation is named in the error,
    # keeping the class (GraphqlError or TransportError) and thus the status.
    def execute(operation_name, operation)
      @client.execute(operation[:query], operation[:variables])
    rescue GraphqlError, TransportError => e
      raise e.class, "GraphQL #{operation_name} failed on '#{name}': #{e.message}"
    end

    protected

    # A PolymorphicManyToOne cannot be joined by Hasura, so its discriminator
    # columns are selected instead and the relation is rebuilt by the serializer
    # from those two values (see materialize_polymorphics). Protected: called on
    # the target collection to resolve nested selections.
    def build_selection(projection)
      selection = projection.columns.reject { |column| column == '*' }

      projection.relations.each do |relation_name, relation_projection|
        field = schema[:fields][relation_name]
        next if field.nil?

        if field.type == 'PolymorphicManyToOne'
          selection << field.foreign_key
          selection << field.foreign_key_type_field
        else
          target = datasource.get_collection(field.foreign_collection)
          nested = target.build_selection(relation_projection)
          selection << "#{relation_name} { #{nested.join(" ")} }"
        end
      end

      selection = selection.uniq
      # An empty projection is a valid toolkit input, but `table { }` is not
      # valid GraphQL: fall back to the primary key.
      selection.empty? ? Array(@table.primary_key.first || column_names.first) : selection
    end

    # The serializer reads the reference off the discriminator columns, so the
    # relation key only carries a placeholder — which has to be non-empty, since
    # an empty hash drops the relation from the JSON:API payload. A type matching
    # no exposed collection stays unresolved: the serializer looks the collection
    # up by that raw value and would fail the whole page. Nested records walk
    # down to their own collection, mirroring build_selection: a projection can
    # reach a polymorphic relation through an ordinary one. Protected, like
    # build_selection, so target collections can be delegated to.
    def materialize_polymorphics(record, projection)
      projection.relations.each do |relation_name, relation_projection|
        field = schema[:fields][relation_name]
        next if field.nil?

        if field.type == 'PolymorphicManyToOne'
          materialize_placeholder(record, relation_name, field)
        else
          materialize_nested(record, relation_name, field, relation_projection)
        end
      end

      record
    end

    private

    def column_names
      @column_names ||= @table.columns.map(&:name)
    end

    # Selects on the schema rather than on the value type, so that a `jsonb`
    # column — whose value is a hash, like a relation payload would be — is kept.
    def writable_columns(data)
      data.select { |key, _| column_names.include?(key.to_s) }
    end

    def materialize_placeholder(record, relation_name, field)
      type_value = record[field.foreign_key_type_field]
      resolvable = type_value && field.foreign_key_targets.key?(type_value.to_s.gsub('::', '__'))
      warn_unknown_type(relation_name, type_value) if type_value && !resolvable

      # An explicit nil check: false is a legitimate key value on a boolean
      # primary key, absent is not.
      record[relation_name] = resolvable && !record[field.foreign_key].nil? ? PLACEHOLDER_REFERENCE : nil
    end

    def materialize_nested(record, relation_name, field, relation_projection)
      nested = record[relation_name]
      target = datasource.get_collection(field.foreign_collection)

      case nested
      when Hash then target.materialize_polymorphics(nested, relation_projection)
      when Array then nested.each { |row| target.materialize_polymorphics(row, relation_projection) }
      end
    end

    def warn_unknown_type(relation_name, type_value)
      @warned_types ||= Set.new
      return unless @warned_types.add?("#{relation_name}/#{type_value}")

      ForestAdminDatasourceGraphqlHasura.logger.warn(
        "[forest_admin_datasource_graphql_hasura] '#{name}.#{relation_name}' references the type " \
        "'#{type_value}', which matches no exposed collection; those references are shown empty. " \
        "Use the 'type_values' option if the Rails class name differs from the table name."
      )
    end

    # Only guards update: a bulk delete with "select all" legitimately carries no
    # condition, and wiping is then the requested semantic.
    def empty_condition?(filter)
      condition = Query::FilterConverter.convert(filter&.condition_tree)

      condition.nil? || condition.empty?
    end
  end
end
