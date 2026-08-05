module ForestAdminDatasourceGraphqlHasura
  module Query
    # Builds Hasura GraphQL operations (queries and mutations) with variables.
    # All methods return { query:, variables: }.
    class QueryBuilder
      class << self
        # selection holds resolved GraphQL fields, nested relations included
        # ("membership { id full_name }").
        def list(table, filter, selection)
          args = []
          var_defs = []
          variables = {}

          where = FilterConverter.convert(filter.condition_tree)

          if where
            var_defs << "$where: #{table}_bool_exp"
            args << 'where: $where'
            variables['where'] = where
          end

          add_sort(table, filter, args, var_defs, variables)
          add_pagination(filter, args, var_defs, variables)

          query = <<~GRAPHQL
            query List#{camelize(table)}#{wrap(var_defs)} {
              #{table}#{wrap(args)} {
                #{selection.join("\n    ")}
              }
            }
          GRAPHQL

          { query: query, variables: variables }
        end

        def create(table, records, selection)
          query = <<~GRAPHQL
            mutation Insert#{camelize(table)}($objects: [#{table}_insert_input!]!) {
              insert_#{table}(objects: $objects) {
                returning {
                  #{selection.join("\n      ")}
                }
              }
            }
          GRAPHQL

          { query: query, variables: { 'objects' => records.map { |record| stringify_keys(record) } } }
        end

        def update(table, filter, patch)
          query = <<~GRAPHQL
            mutation Update#{camelize(table)}($where: #{table}_bool_exp!, $set: #{table}_set_input!) {
              update_#{table}(where: $where, _set: $set) {
                affected_rows
              }
            }
          GRAPHQL

          {
            query: query,
            variables: {
              'where' => FilterConverter.convert(filter.condition_tree) || {},
              'set' => stringify_keys(patch)
            }
          }
        end

        def delete(table, filter)
          query = <<~GRAPHQL
            mutation Delete#{camelize(table)}($where: #{table}_bool_exp!) {
              delete_#{table}(where: $where) {
                affected_rows
              }
            }
          GRAPHQL

          { query: query, variables: { 'where' => FilterConverter.convert(filter.condition_tree) || {} } }
        end

        # extra_where is a raw bool_exp and-combined with the converted filter
        # (the null-bucket query adds `{ fk => { _is_null => true } }`).
        def aggregate(table, filter, aggregation, extra_where: nil)
          args = []
          var_defs = []
          variables = {}

          where = combine(FilterConverter.convert(filter.condition_tree), extra_where)

          if where
            var_defs << "$where: #{table}_bool_exp"
            args << 'where: $where'
            variables['where'] = where
          end

          query = <<~GRAPHQL
            query Aggregate#{camelize(table)}#{wrap(var_defs)} {
              #{table}_aggregate#{wrap(args)} {
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
        def grouped_aggregate(child_table, relation, filter, aggregation, page)
          args = []
          var_defs = ['$parentLimit: Int', '$parentOffset: Int']
          variables = { 'parentLimit' => page[:limit], 'parentOffset' => page[:offset] }
          parent_args = ['limit: $parentLimit', 'offset: $parentOffset', parent_order(relation)]

          where = FilterConverter.convert(filter.condition_tree)

          if where
            var_defs << "$where: #{child_table}_bool_exp"
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

        def aggregation_selection(aggregation)
          operation = aggregation.operation

          if operation == 'Count'
            aggregation.field ? "count(columns: #{aggregation.field})" : 'count'
          else
            "#{operation.downcase} { #{aggregation.field} }"
          end
        end

        private

        def add_sort(table, filter, args, var_defs, variables)
          return unless filter.respond_to?(:sort) && filter.sort&.any?

          var_defs << "$orderBy: [#{table}_order_by!]"
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
