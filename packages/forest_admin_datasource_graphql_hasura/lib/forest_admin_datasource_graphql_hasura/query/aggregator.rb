require 'time'

module ForestAdminDatasourceGraphqlHasura
  module Query
    # Runs Forest aggregations against Hasura on behalf of a collection.
    #
    # Hasura exposes GROUP BY only through a nested `<relation>_aggregate` on a
    # parent object, so a grouped aggregation goes through the parent table and is
    # reduced here rather than by the database.
    class Aggregator
      ForestException = ForestAdminDatasourceToolkit::Exceptions::ForestException

      # Parent rows are read in one page because they are reduced in Ruby; beyond
      # that the chart would be truncated anyway.
      PARENT_LIMIT = 1000

      def initialize(collection)
        @collection = collection
      end

      def run(filter, aggregation, limit)
        validate(aggregation)

        if aggregation.groups.nil? || aggregation.groups.empty?
          simple(filter, aggregation)
        else
          grouped(filter, aggregation, limit)
        end
      end

      private

      def name = @collection.name
      def table_name = @collection.table_name
      def datasource = @collection.datasource
      def fields = @collection.schema[:fields]

      # Aggregation fields are interpolated into the GraphQL document and are the
      # one path the agent does not validate upstream (the charts route passes the
      # request's `aggregateFieldName` straight through).
      def validate(aggregation)
        validate_field(aggregation.field) if aggregation.field
        groups = aggregation.groups || []

        if groups.size > 1
          raise ForestException,
                "Grouping on several fields is not supported by the GraphQL datasource (collection '#{name}')."
        end

        groups.each do |group|
          if group[:operation]
            raise ForestException,
                  "Date grouping is not supported by the GraphQL datasource (collection '#{name}')."
          end

          validate_field(group[:field], allow_relation: true)
        end
      end

      def validate_field(field, allow_relation: false)
        path = field.to_s.split(':')

        unless (allow_relation && path.size <= 2) || path.size == 1
          raise ForestException, "Invalid aggregation field '#{field}' on collection '#{name}'."
        end

        *relations, last = path
        collection = relations.reduce(@collection) { |current, part| collection_through(current, part, field) }

        return unless collection.schema[:fields][last].nil?

        raise ForestException, "Field '#{field}' not found on collection '#{collection.name}'."
      end

      def collection_through(collection, relation_name, field)
        schema = collection.schema[:fields][relation_name]
        raise ForestException, "Field '#{field}' not found on collection '#{collection.name}'." if schema.nil?

        unless schema.type == 'ManyToOne'
          raise ForestException, "Cannot aggregate through '#{relation_name}' on collection '#{collection.name}'."
        end

        datasource.get_collection(schema.foreign_collection)
      end

      def simple(filter, aggregation)
        operation = QueryBuilder.aggregate(table_name, filter, aggregation)
        data = @collection.execute(:aggregate, operation).dig("#{table_name}_aggregate", 'aggregate')

        # One row even when the aggregate is null: the charts route reads
        # `result[0]['value']` unguarded.
        [{ 'value' => extract_value(data, aggregation), 'group' => {} }]
      end

      def grouped(filter, aggregation, limit)
        group_field = aggregation.groups.first[:field]
        relation = find_group_relation(group_field)
        operation = QueryBuilder.grouped_aggregate(table_name, relation, filter, aggregation, PARENT_LIMIT)

        rows = @collection.execute(:aggregate, operation)[relation[:parent_table]] || []
        warn_truncated(relation[:parent_table]) if rows.size >= PARENT_LIMIT

        results = collect_groups(rows, relation, aggregation, group_field)
        limit ? results.first(limit) : results
      end

      def collect_groups(rows, relation, aggregation, group_field)
        values = rows.each_with_object({}) do |row, memo|
          value = extract_value(row.dig("#{relation[:relation_name]}_aggregate", 'aggregate'), aggregation)
          next if childless_parent?(value, aggregation)

          key = row[relation[:parent_field]]
          memo[key] = memo.key?(key) ? merge_values(memo[key], value, aggregation) : value
        end

        values
          .map { |key, value| { 'value' => value, 'group' => { group_field => key } } }
          .sort_by { |row| sortable_value(row['value']) }
          .reverse
      end

      # Two parent rows can share a group value — grouping by a name rather than by
      # the primary key, as leaderboard charts do — and SQL would return them as a
      # single group.
      def merge_values(current, value, aggregation)
        case aggregation.operation
        when 'Count', 'Sum' then sortable_value(current) + sortable_value(value)
        when 'Max' then sortable_value(value) > sortable_value(current) ? value : current
        when 'Min' then sortable_value(value) < sortable_value(current) ? value : current
        else
          raise ForestException,
                "#{aggregation.operation} cannot be grouped on '#{name}' by a value several parent rows " \
                'share: the result would not be exact. Group on the foreign key instead.'
        end
      end

      # A parent with no child row is what SQL grouping would leave out. A zero
      # `count(columns: field)` is different: rows exist, they just all hold null.
      def childless_parent?(value, aggregation)
        value.nil? || (aggregation.operation == 'Count' && aggregation.field.nil? && value.to_i.zero?)
      end

      # Accepts a foreign key (`membership_id`) or a path through a ManyToOne
      # (`membership:full_name`, what leaderboard charts request).
      def find_group_relation(group_field)
        field_name, parent_column = group_field.split(':')
        relation, foreign_key = resolve_group_relation(field_name)
        reverse = relation && reverse_relation_name(relation, foreign_key)

        unless reverse
          raise ForestException,
                "Group by '#{group_field}' is not supported: the GraphQL datasource groups through a " \
                "foreign key whose reverse relationship is declared in Hasura (collection '#{name}')."
        end

        parent = datasource.get_collection(relation.foreign_collection)

        {
          parent_table: parent.table_name,
          parent_field: parent_column || relation.foreign_key_target,
          relation_name: reverse
        }
      end

      def resolve_group_relation(field_name)
        field = fields[field_name]
        return [field, field.foreign_key] if field&.type == 'ManyToOne'

        [fields.values.find { |f| f.type == 'ManyToOne' && f.foreign_key == field_name }, field_name]
      end

      def reverse_relation_name(relation, foreign_key)
        parent = datasource.get_collection(relation.foreign_collection)

        parent.schema[:fields].each do |relation_name, field|
          next unless field.type == 'OneToMany' &&
                      field.foreign_collection == name &&
                      field.origin_key == foreign_key

          return relation_name
        end

        nil
      end

      def warn_truncated(parent_table)
        ForestAdminDatasourceGraphqlHasura.logger.warn(
          "[forest_admin_datasource_graphql_hasura] Grouped aggregation on '#{name}' stopped after " \
          "#{PARENT_LIMIT} '#{parent_table}' rows; the result may be incomplete."
        )
      end

      # Hasura returns bigint/numeric/money as JSON strings to preserve precision,
      # and Max/Min aggregate dates, which have to order by instant rather than
      # collapse to zero.
      def sortable_value(value)
        case value
        when Numeric then value
        when String then Float(value, exception: false) || time_value(value)
        else 0
        end
      end

      def time_value(value)
        Time.parse(value).to_f
      rescue ArgumentError, TypeError
        0
      end

      def extract_value(data, aggregation)
        return nil if data.nil?

        if aggregation.operation == 'Count'
          data['count']
        else
          data.dig(aggregation.operation.downcase, aggregation.field)
        end
      end
    end
  end
end
