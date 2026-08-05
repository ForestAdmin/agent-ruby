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

      # Parent rows are reduced in Ruby, so they are paginated by PARENT_PAGE and
      # capped at MAX_PARENT_ROWS: past the cap the chart fails with a clear error
      # rather than silently charting a subset.
      PARENT_PAGE = 1000
      MAX_PARENT_ROWS = 10_000

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
        values = collect_groups(fetch_parent_rows(relation, filter, aggregation), relation, aggregation)
        add_null_group(values, relation, filter, aggregation)

        results = values
                  .map { |key, value| { 'value' => value, 'group' => { group_field => key } } }
                  .sort_by { |row| comparable(row['value']) }
                  .reverse
        limit ? results.first(limit) : results
      end

      def fetch_parent_rows(relation, filter, aggregation)
        rows = []
        offset = 0

        loop do
          operation = QueryBuilder.grouped_aggregate(table_name, relation, filter, aggregation,
                                                     { limit: PARENT_PAGE, offset: offset })
          page = @collection.execute(:aggregate, operation)[relation[:parent_table]] || []
          rows.concat(page)

          return rows if page.size < PARENT_PAGE

          if rows.size >= MAX_PARENT_ROWS
            raise ForestException,
                  "Grouped aggregation on '#{name}' spans more than #{MAX_PARENT_ROWS} " \
                  "'#{relation[:parent_table]}' rows; narrow the chart filter."
          end

          offset += PARENT_PAGE
        end
      end

      def collect_groups(rows, relation, aggregation)
        rows.each_with_object({}) do |row, memo|
          value = extract_value(row.dig("#{relation[:relation_name]}_aggregate", 'aggregate'), aggregation)
          next if childless_parent?(value, aggregation)

          key = row[relation[:parent_field]]
          memo[key] = memo.key?(key) ? merge_values(memo[key], value, aggregation) : value
        end
      end

      # SQL grouping puts rows whose foreign key is NULL in a bucket of their own;
      # the parent-table detour cannot see them, so they are aggregated apart. The
      # nil key can pre-exist (a parent whose grouped column is null): both are the
      # NULL group of a LEFT JOIN, so they merge.
      def add_null_group(values, relation, filter, aggregation)
        foreign_key = fields[relation[:foreign_key]]
        return if foreign_key.nil? || foreign_key.validation.any? # non-nullable: no orphan rows

        operation = QueryBuilder.aggregate(table_name, filter, aggregation,
                                           extra_where: { relation[:foreign_key] => { '_is_null' => true } })
        data = @collection.execute(:aggregate, operation).dig("#{table_name}_aggregate", 'aggregate')
        value = extract_value(data, aggregation)
        return if childless_parent?(value, aggregation)

        values[nil] = values.key?(nil) ? merge_values(values[nil], value, aggregation) : value
      end

      # Two parent rows can share a group value — grouping by a name rather than by
      # the primary key, as leaderboard charts do — and SQL would return them as a
      # single group.
      def merge_values(current, value, aggregation)
        case aggregation.operation
        when 'Count', 'Sum' then add(current, value)
        when 'Max' then (comparable(value) <=> comparable(current)).positive? ? value : current
        when 'Min' then (comparable(value) <=> comparable(current)).negative? ? value : current
        else
          raise ForestException,
                "#{aggregation.operation} cannot be grouped on '#{name}' by a value several parent rows " \
                'share: the result would not be exact. Group on the foreign key instead.'
        end
      end

      # Hasura sends bigint and numeric as JSON strings to keep a precision a Float
      # would lose, so whole numbers are added as Integers, which Ruby does not cap.
      def add(current, value)
        left = numeric(current)
        right = numeric(value)

        left + right
      end

      def numeric(value)
        case value
        when Integer, Float then value
        when String then value.match?(/\A-?\d+\z/) ? value.to_i : Float(value, exception: false) || 0
        else 0
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
          relation_name: reverse,
          foreign_key: foreign_key,
          parent_order_fields: primary_keys_of(parent)
        }
      end

      # Offset pagination needs a stable order, which only the primary key gives.
      def primary_keys_of(collection)
        collection.schema[:fields]
                  .select { |_, field| field.respond_to?(:is_primary_key) && field.is_primary_key }
                  .keys
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

      # Aggregate values are not necessarily numbers: Hasura sends bigint and
      # numeric as strings, and Max/Min aggregate dates as well as text. The tuple
      # orders numbers and instants together, then text lexically, and stays
      # comparable across rows so `sort_by` and Max/Min agree.
      def comparable(value)
        case value
        when Numeric then [0, value.to_f, '']
        when String then comparable_string(value)
        else [2, 0.0, '']
        end
      end

      def comparable_string(value)
        number = Float(value, exception: false)
        return [0, number, ''] if number

        instant = time_value(value)
        instant ? [0, instant, ''] : [1, 0.0, value]
      end

      def time_value(value)
        Time.parse(value).to_f
      rescue ArgumentError, TypeError
        nil
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
