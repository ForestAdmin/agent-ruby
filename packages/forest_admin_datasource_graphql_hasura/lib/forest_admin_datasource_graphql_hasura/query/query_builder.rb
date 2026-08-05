module ForestAdminDatasourceGraphqlHasura
  module Query
    # Builds Hasura GraphQL operations (queries and mutations) with variables.
    # All methods return { query:, variables: }.
    #
    # names is { root:, base:, aggregate:, insert:, update:, delete: }: `root`
    # is the select root field, `base` (the GraphQL type name) is what the
    # generated type names derive from — `<base>_bool_exp`,
    # `<base>_insert_input`… — and the operation roots carry their resolved
    # names, custom_root_fields applied when the metadata declares them.
    class QueryBuilder
      class << self
        # selection holds resolved GraphQL fields, nested relations included
        # ("membership { id full_name }").
        def list(names, filter, selection)
          args = []
          var_defs = []
          variables = {}

          where = FilterConverter.convert(filter.condition_tree)

          if where
            var_defs << "$where: #{names[:base]}_bool_exp"
            args << 'where: $where'
            variables['where'] = where
          end

          add_sort(names, filter, args, var_defs, variables)
          add_pagination(filter, args, var_defs, variables)

          query = <<~GRAPHQL
            query List#{camelize(names[:root])}#{wrap(var_defs)} {
              #{names[:root]}#{wrap(args)} {
                #{selection.join("\n    ")}
              }
            }
          GRAPHQL

          { query: query, variables: variables }
        end

        def create(names, records, selection)
          query = <<~GRAPHQL
            mutation Insert#{camelize(names[:base])}($objects: [#{names[:base]}_insert_input!]!) {
              #{names[:insert]}(objects: $objects) {
                returning {
                  #{selection.join("\n      ")}
                }
              }
            }
          GRAPHQL

          { query: query, variables: { 'objects' => records.map { |record| stringify_keys(record) } } }
        end

        def update(names, filter, patch)
          where = FilterConverter.convert(filter.condition_tree)

          # Backstop behind the collection guard: `{}` is vacuously true for
          # Hasura, so a filterless update would rewrite the whole table.
          if where.nil?
            raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                  "Refusing to update every row of '#{names[:root]}': the filter carries no condition."
          end

          query = <<~GRAPHQL
            mutation Update#{camelize(names[:base])}($where: #{names[:base]}_bool_exp!, $set: #{names[:base]}_set_input!) {
              #{names[:update]}(where: $where, _set: $set) {
                affected_rows
              }
            }
          GRAPHQL

          { query: query, variables: { 'where' => where, 'set' => stringify_keys(patch) } }
        end

        def delete(names, filter)
          query = <<~GRAPHQL
            mutation Delete#{camelize(names[:base])}($where: #{names[:base]}_bool_exp!) {
              #{names[:delete]}(where: $where) {
                affected_rows
              }
            }
          GRAPHQL

          # `{}` (match all) is deliberate here: a bulk delete with "select all"
          # legitimately carries no condition, and wiping is the requested semantic.
          { query: query, variables: { 'where' => FilterConverter.convert(filter.condition_tree) || {} } }
        end

        # extra_where is a raw bool_exp and-combined with the converted filter
        # (the null-bucket query adds `{ fk => { _is_null => true } }`).
        def aggregate(names, filter, aggregation, extra_where: nil)
          args = []
          var_defs = []
          variables = {}

          where = combine(FilterConverter.convert(filter.condition_tree), extra_where)

          if where
            var_defs << "$where: #{names[:base]}_bool_exp"
            args << 'where: $where'
            variables['where'] = where
          end

          query = <<~GRAPHQL
            query Aggregate#{camelize(names[:base])}#{wrap(var_defs)} {
              #{names[:aggregate]}#{wrap(args)} {
                aggregate {
                  #{aggregation_selection(aggregation)}
                }
              }
            }
          GRAPHQL

          { query: query, variables: variables }
        end

        # relation is { parent_table:, parent_field:, relation_name:, parent_order_fields: },
        # page is { limit:, offset: }. Parents are ordered by their primary key so
        # offset pagination is stable, and filtered by the chart's predicate through
        # the relationship, so the pages only walk parents owning at least one
        # matching child row.
        def grouped_aggregate(names, relation, filter, aggregation, page)
          args = []
          var_defs = ['$parentLimit: Int', '$parentOffset: Int']
          variables = { 'parentLimit' => page[:limit], 'parentOffset' => page[:offset] }
          parent_args = ['limit: $parentLimit', 'offset: $parentOffset', parent_order(relation)]

          where = FilterConverter.convert(filter.condition_tree)

          if where
            var_defs << "$where: #{names[:base]}_bool_exp"
            args << 'where: $where'
            parent_args << "where: { #{relation[:relation_name]}: $where }"
            variables['where'] = where
          end

          query = <<~GRAPHQL
            query Aggregate#{camelize(relation[:parent_table])}#{wrap(var_defs)} {
              #{relation[:parent_table]}#{wrap(parent_args)} {
                #{relation[:parent_field]}
                #{relation[:relation_name]}_aggregate#{wrap(args)} {
                  aggregate {
                    #{aggregation_selection(aggregation)}
                  }
                }
              }
            }
          GRAPHQL

          { query: query, variables: variables }
        end

        # Distinct values of `column` among rows without a matching parent — the
        # dangling foreign keys a grouped chart must keep as groups of their own.
        # distinct_on requires the matching order_by.
        def orphan_keys(names, filter, column, relation_name, limit)
          where = combine(
            FilterConverter.convert(filter.condition_tree),
            { '_and' => [{ '_not' => { relation_name => {} } }, { column => { '_is_null' => false } }] }
          )

          query = <<~GRAPHQL
            query OrphanKeys#{camelize(names[:root])}($where: #{names[:base]}_bool_exp, $limit: Int) {
              #{names[:root]}(where: $where, distinct_on: [#{column}], order_by: [{ #{column}: asc }], limit: $limit) {
                #{column}
              }
            }
          GRAPHQL

          { query: query, variables: { 'where' => where, 'limit' => limit } }
        end

        # row_count tells a group with no rows at all (SQL grouping omits it)
        # from one whose rows exist but hold NULL in the aggregated column
        # (SQL keeps it, at zero for a count and at NULL otherwise).
        def aggregation_selection(aggregation)
          "#{operation_selection(aggregation)}#{avg_merge_selection(aggregation)}\nrow_count: count"
        end

        def operation_selection(aggregation)
          if aggregation.operation == 'Count'
            aggregation.field ? "count(columns: #{aggregation.field})" : 'count'
          else
            "#{aggregation.operation.downcase} { #{aggregation.field} }"
          end
        end

        # An average cannot be merged across parent rows sharing a group value;
        # its sum and non-null count can, weighting it exactly.
        def avg_merge_selection(aggregation)
          return '' unless aggregation.operation == 'Avg'

          "\navg_sum: sum { #{aggregation.field} }\navg_count: count(columns: #{aggregation.field})"
        end

        private

        def add_sort(names, filter, args, var_defs, variables)
          return unless filter.respond_to?(:sort) && filter.sort&.any?

          var_defs << "$orderBy: [#{names[:base]}_order_by!]"
          args << 'order_by: $orderBy'
          variables['orderBy'] = convert_sort(filter.sort)
        end

        def add_pagination(filter, args, var_defs, variables)
          page = filter.respond_to?(:page) ? filter.page : nil

          if page&.limit
            var_defs << '$limit: Int'
            args << 'limit: $limit'
            variables['limit'] = page.limit
          end

          return unless page&.offset&.positive?

          var_defs << '$offset: Int'
          args << 'offset: $offset'
          variables['offset'] = page.offset
        end

        def convert_sort(sort)
          sort.map do |clause|
            direction = clause[:ascending] ? 'asc' : 'desc'
            parts = clause[:field].split(':')

            parts.reverse.reduce(direction) { |memo, part| { part => memo } }
          end
        end

        # Values are kept as submitted, nil included: a column left empty has to
        # be written as null rather than fall back to its database default. The
        # caller already restricted the keys to real columns.
        def stringify_keys(record)
          record.to_h { |key, value| [key.to_s, value] }
        end

        def parent_order(relation)
          "order_by: [#{relation[:parent_order_fields].map { |field| "{ #{field}: asc }" }.join(", ")}]"
        end

        def combine(where, extra)
          return where if extra.nil?

          where ? { '_and' => [where, extra] } : extra
        end

        def wrap(parts)
          parts.empty? ? '' : "(#{parts.join(", ")})"
        end

        def camelize(name)
          name.split('_').map(&:capitalize).join
        end
      end
    end
  end
end
