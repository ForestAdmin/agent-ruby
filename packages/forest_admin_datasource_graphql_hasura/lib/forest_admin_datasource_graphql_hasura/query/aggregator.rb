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

      # At most this many distinct dangling foreign keys get a group of their
      # own; beyond that the data is corrupt enough to deserve an error.
      DANGLING_KEYS_LIMIT = 100

      def initialize(collection)
        @collection = collection
      end

      def run(filter, aggregation, limit)
        validate(aggregation)
        @date_field = date_field?(aggregation)

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
        validate_field(aggregation.field, column_only: true) if aggregation.field

        # Without a field, `sum { }` would be an empty GraphQL selection set.
        if aggregation.field.nil? && aggregation.operation != 'Count'
          raise ForestException,
                "#{aggregation.operation} requires a field on collection '#{name}'."
        end

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

      # column_only rejects a relation as the aggregated field (`sum { membership }`
      # is not valid GraphQL); a group field may end on a ManyToOne, which stands
      # for its foreign key.
      def validate_field(field, allow_relation: false, column_only: false)
        path = field.to_s.split(':')

        unless (allow_relation && path.size <= 2) || path.size == 1
          raise ForestException, "Invalid aggregation field '#{field}' on collection '#{name}'."
        end

        *relations, last = path
        collection = relations.reduce(@collection) { |current, part| collection_through(current, part, field) }
        target = collection.schema[:fields][last]

        raise ForestException, "Field '#{field}' not found on collection '#{collection.name}'." if target.nil?

        return unless column_only && target.type != 'Column'

        raise ForestException,
              "Cannot aggregate on '#{field}': it is a relation, not a column (collection '#{name}')."
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
        add_orphan_groups(values, relation, filter, aggregation)

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

          # The strict comparison lets exactly MAX_PARENT_ROWS through (a final
          # empty page then closes the walk); anything beyond fails, even on a
          # partial page, so the cap the README documents is the cap enforced.
          if rows.size > MAX_PARENT_ROWS
            raise ForestException,
                  "Grouped aggregation on '#{name}' spans more than #{MAX_PARENT_ROWS} " \
                  "'#{relation[:parent_table]}' rows; narrow the chart filter."
          end

          return rows if page.size < PARENT_PAGE

          offset += PARENT_PAGE
        end
      end

      def collect_groups(rows, relation, aggregation)
        rows.each_with_object({}) do |row, memo|
          data = row.dig("#{relation[:relation_name]}_aggregate", 'aggregate')
          next if childless?(data, aggregation)

          value = extract_value(data, aggregation)
          key = row[relation[:parent_field]]
          memo[key] = memo.key?(key) ? merge_values(memo[key], value, aggregation) : value
        end
      end

      # Rows without a matching parent are invisible to the parent-table detour.
      # Grouped by a parent column, they are the NULL group of a LEFT JOIN — nil
      # and dangling foreign keys alike (`_not: { relation: {} }` selects both).
      # Grouped by the foreign key itself, SQL keeps each dangling key as a group
      # of its own: those keys are enumerated and aggregated one by one, and only
      # truly NULL keys fall into the nil bucket.
      def add_orphan_groups(values, relation, filter, aggregation)
        return unless relation[:orphans_possible]

        if relation[:fk_grouping]
          dangling_keys(relation, filter).each do |key|
            add_orphan_group(values, key, filter, aggregation, { relation[:foreign_key] => { '_eq' => key } })
          end
          add_orphan_group(values, nil, filter, aggregation,
                           { relation[:foreign_key] => { '_is_null' => true } })
        else
          # The nil key can pre-exist (a parent whose grouped column is null):
          # both are the NULL group of a LEFT JOIN, so they merge.
          add_orphan_group(values, nil, filter, aggregation,
                           { '_not' => { relation[:child_relation_name] => {} } })
        end
      end

      def add_orphan_group(values, key, filter, aggregation, extra_where)
        operation = QueryBuilder.aggregate(table_name, filter, aggregation, extra_where: extra_where)
        data = @collection.execute(:aggregate, operation).dig("#{table_name}_aggregate", 'aggregate')
        return if childless?(data, aggregation)

        value = extract_value(data, aggregation)
        values[key] = values.key?(key) ? merge_values(values[key], value, aggregation) : value
      end

      def dangling_keys(relation, filter)
        operation = QueryBuilder.orphan_keys(table_name, filter, relation[:foreign_key],
                                             relation[:child_relation_name], DANGLING_KEYS_LIMIT)
        rows = @collection.execute(:aggregate, operation)[table_name] || []
        keys = rows.map { |row| row[relation[:foreign_key]] }

        if keys.size >= DANGLING_KEYS_LIMIT
          raise ForestException,
                "Grouped aggregation on '#{name}': more than #{DANGLING_KEYS_LIMIT} distinct " \
                "'#{relation[:foreign_key]}' values reference no parent row; clean the data up " \
                'or narrow the chart filter.'
        end

        keys
      end

      # Two parent rows can share a group value — grouping by a name rather than by
      # the primary key, as leaderboard charts do — and SQL would return them as a
      # single group. A NULL side is ignored, as SQL aggregates ignore NULLs, and
      # two NULL sides stay NULL.
      def merge_values(current, value, aggregation)
        return current if value.nil?
        return value if current.nil?

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

      # A group with no rows at all is what SQL grouping leaves out. The
      # `row_count` alias tells it from a group whose rows exist but hold NULL in
      # the aggregated column — SQL keeps that one: a zero `count(columns: x)`,
      # a NULL Sum/Max/Min. The value-based fallback covers a response missing
      # the alias.
      def childless?(data, aggregation)
        return true if data.nil?
        return data['row_count'].to_i.zero? if data.key?('row_count')

        value = extract_value(data, aggregation)
        value.nil? || (aggregation.operation == 'Count' && aggregation.field.nil? && value.to_i.zero?)
      end

      # Accepts a foreign key (`membership_id`) or a path through a ManyToOne
      # (`membership:full_name`, what leaderboard charts request).
      def find_group_relation(group_field)
        field_name, parent_column = group_field.split(':')
        relation_name, relation, foreign_key = resolve_group_relation(field_name)
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
          child_relation_name: relation_name,
          foreign_key: foreign_key,
          fk_grouping: parent_column.nil?,
          parent_order_fields: primary_keys_of(parent),
          orphans_possible: orphans_possible?(relation_name, relation)
        }
      end

      # A NOT NULL foreign key backed by a real constraint cannot reference a
      # missing parent, so the orphan query would be a wasted round trip. A
      # manual relationship (or one whose backing is unknown) can dangle even
      # on a NOT NULL column.
      def orphans_possible?(relation_name, relation)
        foreign_key = fields[relation.foreign_key]
        nullable = foreign_key.nil? || foreign_key.validation.empty?

        nullable || !@collection.constraint_backed?(relation_name)
      end

      # Offset pagination needs a stable order, which only the primary key gives.
      def primary_keys_of(collection)
        collection.schema[:fields]
                  .select { |_, field| field.respond_to?(:is_primary_key) && field.is_primary_key }
                  .keys
      end

      # Returns [relation_name, relation_schema, foreign_key]. The relation name
      # is also the Hasura object relationship on the child table, which the
      # orphan query of add_null_group negates.
      def resolve_group_relation(field_name)
        field = fields[field_name]
        return [field_name, field, field.foreign_key] if field&.type == 'ManyToOne'

        name, relation = fields.find { |_, f| f.type == 'ManyToOne' && f.foreign_key == field_name }

        [name, relation, field_name]
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
      # comparable across rows so `sort_by` and Max/Min agree. Whole numbers are
      # kept as Integers — Ruby compares them with Floats exactly — because a
      # bigint rounded through a Float would tie with its neighbours.
      def comparable(value)
        case value
        when Numeric then [0, value, '']
        when String then comparable_string(value)
        # NULL groups (rows whose aggregated column is all NULL) sort last.
        else [-1, 0.0, '']
        end
      end

      # Strings reaching here belong to non-numeric columns — numeric ones were
      # normalized at extraction. Date columns order as instants (offsets make
      # lexical ordering lie); anything else orders lexically, like SQL collates,
      # even when a text value happens to look like a date or a number.
      def comparable_string(value)
        instant = @date_field ? time_value(value) : nil

        instant ? [0, instant, ''] : [1, 0.0, value]
      end

      def time_value(value)
        Time.parse(value).to_f
      rescue ArgumentError, TypeError
        nil
      end

      # Hasura serializes bigint and numeric aggregates as JSON strings; a chart
      # value must be a number, and one merged in Ruby must not differ in type
      # from one straight off the wire, so numeric columns are normalized here.
      def extract_value(data, aggregation)
        return nil if data.nil?

        value = if aggregation.operation == 'Count'
                  data['count']
                else
                  data.dig(aggregation.operation.downcase, aggregation.field)
                end

        value.is_a?(String) && number_field?(aggregation) ? numeric(value) : value
      end

      def number_field?(aggregation)
        aggregation.field && fields[aggregation.field]&.column_type == 'Number'
      end

      def date_field?(aggregation)
        aggregation.field && %w[Date Dateonly Time].include?(fields[aggregation.field]&.column_type)
      end
    end
  end
end
