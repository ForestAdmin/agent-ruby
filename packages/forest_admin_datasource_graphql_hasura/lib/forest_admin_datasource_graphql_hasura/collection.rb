module ForestAdminDatasourceGraphqlHasura
  class Collection < ForestAdminDatasourceToolkit::Collection
    ForestException = ForestAdminDatasourceToolkit::Exceptions::ForestException
    Projection = ForestAdminDatasourceToolkit::Components::Query::Projection

    GROUPED_AGGREGATE_PARENT_LIMIT = 1000
    PLACEHOLDER_REFERENCE = { '*' => nil }.freeze

    attr_reader :table_name

    def initialize(datasource, table, client, converter)
      super(datasource, converter.collection_name_of(table.name))

      @table = table
      @table_name = table.name
      @client = client
      @converter = converter

      add_fields(converter.build_fields(table))
      enable_count
      schema[:aggregation_capabilities][:supported_date_operations] = []
    end

    def list(_caller, filter, projection)
      selection = build_selection(projection)
      operation = Query::QueryBuilder.list(@table_name, filter, selection)
      records = execute(:list, operation)[@table_name] || []

      records.map { |record| materialize_polymorphics(record, projection) }
    end

    def create(_caller, data)
      operation = Query::QueryBuilder.create(@table_name, [writable_columns(data)], column_names)
      returning = execute(:create, operation).dig("insert_#{@table_name}", 'returning')

      raise GraphqlError, "No record returned by insert_#{@table_name}" if returning.nil? || returning.empty?

      returning.first
    end

    def update(_caller, filter, data)
      if empty_condition?(filter)
        raise ForestException,
              "Refusing to update every row of '#{name}': the filter carries no condition."
      end

      operation = Query::QueryBuilder.update(@table_name, filter, writable_columns(data))
      execute(:update, operation)
    end

    def delete(_caller, filter)
      operation = Query::QueryBuilder.delete(@table_name, filter)
      execute(:delete, operation)
    end

    def aggregate(_caller, filter, aggregation, limit = nil)
      validate_aggregation(aggregation)

      if aggregation.groups.nil? || aggregation.groups.empty?
        simple_aggregate(filter, aggregation)
      else
        grouped_aggregate(filter, aggregation, limit)
      end
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

    # Aggregation fields are interpolated into the GraphQL document and are the
    # one path the agent does not validate upstream (the charts route passes the
    # request's `aggregateFieldName` straight through).
    def validate_aggregation(aggregation)
      validate_aggregation_field(aggregation.field) if aggregation.field

      (aggregation.groups || []).each do |group|
        if group[:operation]
          raise ForestException,
                "Date grouping is not supported by the GraphQL datasource (collection '#{name}')."
        end

        validate_aggregation_field(group[:field], allow_relation: true)
      end
    end

    def validate_aggregation_field(field, allow_relation: false)
      path = field.to_s.split(':')

      unless (allow_relation && path.size <= 2) || path.size == 1
        raise ForestException, "Invalid aggregation field '#{field}' on collection '#{name}'."
      end

      collection = self
      path.each_with_index do |part, index|
        schema = collection.schema[:fields][part]
        raise ForestException, "Field '#{field}' not found on collection '#{collection.name}'." if schema.nil?
        next if index == path.size - 1

        unless schema.type == 'ManyToOne'
          raise ForestException, "Cannot aggregate through '#{part}' on collection '#{collection.name}'."
        end

        collection = datasource.get_collection(schema.foreign_collection)
      end
    end

    def execute(operation_name, operation)
      @client.execute(operation[:query], operation[:variables])
    rescue GraphqlError => e
      raise GraphqlError, "GraphQL #{operation_name} failed on '#{name}': #{e.message}"
    end

    # A PolymorphicManyToOne cannot be joined by Hasura, so its discriminator
    # columns are selected instead and the relation is rebuilt by the serializer
    # from those two values (see materialize_polymorphics).
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
          nested = target.send(:build_selection, relation_projection)
          selection << "#{relation_name} { #{nested.join(" ")} }"
        end
      end

      selection.uniq
    end

    # The serializer reads the reference off the discriminator columns, so the
    # relation key only carries a placeholder — which has to be non-empty, since
    # an empty hash drops the relation from the JSON:API payload. A type matching
    # no exposed collection stays unresolved: the serializer looks the collection
    # up by that raw value and would fail the whole page.
    def materialize_polymorphics(record, projection)
      projection.relations.each_key do |relation_name|
        field = schema[:fields][relation_name]
        next unless field&.type == 'PolymorphicManyToOne'

        type_value = record[field.foreign_key_type_field]
        resolvable = type_value && field.foreign_key_targets.key?(type_value.to_s.gsub('::', '__'))
        warn_unknown_type(relation_name, type_value) if type_value && !resolvable

        record[relation_name] = resolvable && record[field.foreign_key] ? PLACEHOLDER_REFERENCE : nil
      end

      record
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

    def simple_aggregate(filter, aggregation)
      operation = Query::QueryBuilder.aggregate(@table_name, filter, aggregation)
      data = execute(:aggregate, operation).dig("#{@table_name}_aggregate", 'aggregate')

      # One row even when the aggregate is null: the charts route reads
      # `result[0]['value']` unguarded.
      [{ 'value' => extract_aggregate_value(data, aggregation), 'group' => {} }]
    end

    # Hasura exposes GROUP BY only through a nested `<relation>_aggregate` on a
    # parent object, hence the detour through the parent table and the reduction
    # in Ruby.
    def grouped_aggregate(filter, aggregation, limit)
      group_field = aggregation.groups.first[:field]
      relation = find_group_relation(group_field)

      operation = Query::QueryBuilder.grouped_aggregate(
        @table_name, relation, filter, aggregation, GROUPED_AGGREGATE_PARENT_LIMIT
      )

      rows = execute(:aggregate, operation)[relation[:parent_table]] || []
      warn_truncated_groups(relation[:parent_table]) if rows.size >= GROUPED_AGGREGATE_PARENT_LIMIT

      results = rows.filter_map do |row|
        value = extract_aggregate_value(row.dig("#{relation[:relation_name]}_aggregate", 'aggregate'), aggregation)
        next if childless_parent?(value, aggregation)

        { 'value' => value, 'group' => { group_field => row[relation[:parent_field]] } }
      end

      results = results.sort_by { |row| sortable_value(row['value']) }.reverse
      limit ? results.first(limit) : results
    end

    # A `Sum` adding up to zero is a real group, unlike a parent that simply has
    # no child row — which SQL grouping would not return either.
    def childless_parent?(value, aggregation)
      value.nil? || (aggregation.operation == 'Count' && value.to_i.zero?)
    end

    # Accepts a foreign key (`membership_id`) or a path through a ManyToOne
    # (`membership:full_name`, what leaderboard charts request).
    def find_group_relation(group_field)
      field_name, parent_column = group_field.split(':')
      field = schema[:fields][field_name]

      relation, foreign_key =
        if field&.type == 'ManyToOne'
          [field, field.foreign_key]
        else
          [schema[:fields].values.find { |f| f.type == 'ManyToOne' && f.foreign_key == field_name }, field_name]
        end

      if relation
        parent = datasource.get_collection(relation.foreign_collection)
        reverse = reverse_relation_name(parent, foreign_key)

        if reverse
          return {
            parent_table: parent.table_name,
            parent_field: parent_column || relation.foreign_key_target,
            relation_name: reverse
          }
        end
      end

      raise ForestException,
            "Group by '#{group_field}' is not supported: the GraphQL datasource groups through a " \
            "foreign key whose reverse relationship is declared in Hasura (collection '#{name}')."
    end

    def reverse_relation_name(parent, foreign_key)
      parent.schema[:fields].each do |relation_name, field|
        next unless field.type == 'OneToMany' &&
                    field.foreign_collection == name &&
                    field.origin_key == foreign_key

        return relation_name
      end

      nil
    end

    def warn_truncated_groups(parent_table)
      ForestAdminDatasourceGraphqlHasura.logger.warn(
        "[forest_admin_datasource_graphql_hasura] Grouped aggregation on '#{name}' stopped after " \
        "#{GROUPED_AGGREGATE_PARENT_LIMIT} '#{parent_table}' rows; the result may be incomplete."
      )
    end

    # Hasura returns bigint/numeric/money as JSON strings to preserve precision,
    # and Max/Min may aggregate dates.
    def sortable_value(value)
      case value
      when Numeric then value
      when String then Float(value, exception: false) || 0
      else 0
      end
    end

    def extract_aggregate_value(data, aggregation)
      return nil if data.nil?

      if aggregation.operation == 'Count'
        data['count']
      else
        data.dig(aggregation.operation.downcase, aggregation.field)
      end
    end

    # Only guards update: a bulk delete with "select all" legitimately carries no
    # condition, and wiping is then the requested semantic.
    def empty_condition?(filter)
      condition = Query::FilterConverter.convert(filter&.condition_tree)

      condition.nil? || condition.empty?
    end
  end
end
