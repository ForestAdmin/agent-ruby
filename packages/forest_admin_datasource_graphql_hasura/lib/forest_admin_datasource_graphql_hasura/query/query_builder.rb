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

          { query: query, variables: { 'objects' => records.map { |record| clean_record(record) } } }
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
              'set' => clean_record(patch, keep_nil: true)
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

        def aggregate(table, filter, aggregation)
          args = []
          var_defs = []
          variables = {}

          where = FilterConverter.convert(filter.condition_tree)

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

        # relation is { parent_table:, parent_field:, relation_name: }.
        def grouped_aggregate(child_table, relation, filter, aggregation, parent_limit)
          args = []
          var_defs = ['$parentLimit: Int']
          variables = { 'parentLimit' => parent_limit }

          where = FilterConverter.convert(filter.condition_tree)

          if where
            var_defs << "$where: #{child_table}_bool_exp"
            args << 'where: $where'
            variables['where'] = where
          end

          query = <<~GRAPHQL
            query Aggregate#{camelize(relation[:parent_table])}#{wrap(var_defs)} {
              #{relation[:parent_table]}(limit: $parentLimit) {
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

        # Nils are dropped on insert so database defaults apply, and kept on
        # update so a field can be cleared.
        def clean_record(record, keep_nil: false)
          record.each_with_object({}) do |(key, value), memo|
            next if value.nil? && !keep_nil

            memo[key.to_s] = value
          end
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
