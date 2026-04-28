module ForestAdminDatasourceSnowflake
  module Utils
    class Query
      Operators           = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
      ConditionTreeBranch = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
      ConditionTreeLeaf   = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

      def initialize(collection, projection: nil, filter: nil, aggregation: nil, limit: nil)
        @collection  = collection
        @projection  = projection
        @filter      = filter
        @aggregation = aggregation
        @limit       = limit
        @binds       = []
      end

      def to_sql
        @binds = []
        cols = @projection ? @projection.columns.map { |c| q(c) } : ['*']
        sql  = "SELECT #{cols.join(", ")} FROM #{q(@collection.table_name)}"

        where = build_where_clause(@filter&.condition_tree)
        sql << " WHERE #{where}" if where

        order_by = build_order_by(@filter&.sort)
        sql << " ORDER BY #{order_by}" if order_by

        if @filter&.page
          limit  = @filter.page.respond_to?(:limit)  ? @filter.page.limit  : nil
          offset = @filter.page.respond_to?(:offset) ? @filter.page.offset : nil
          sql << " LIMIT #{Integer(limit)}" if limit
          sql << " OFFSET #{Integer(offset)}" if offset
        end

        [sql, @binds]
      end

      def to_aggregate_sql
        @binds = []
        op_expr = build_aggregation_expression(@aggregation)

        group_cols = (@aggregation.groups || []).map { |g| g[:field] }
        select_cols = [op_expr, *group_cols.map { |c| q(c) }]
        sql = "SELECT #{select_cols.join(", ")} FROM #{q(@collection.table_name)}"

        where = build_where_clause(@filter&.condition_tree)
        sql << " WHERE #{where}" if where

        sql << " GROUP BY #{group_cols.map { |c| q(c) }.join(", ")}" if group_cols.any?
        sql << " LIMIT #{Integer(@limit)}" if @limit

        [sql, @binds, group_cols]
      end

      private

      def q(identifier)
        Identifier.quote(identifier)
      end

      def build_aggregation_expression(aggregation)
        op    = aggregation.operation.to_s.upcase
        field = aggregation.field

        case op
        when 'COUNT'
          field ? "COUNT(#{q(field)})" : 'COUNT(*)'
        when 'SUM', 'AVG', 'MIN', 'MAX'
          "#{op}(#{q(field)})"
        else
          raise ForestAdminDatasourceSnowflake::Error, "Unsupported aggregation operation: #{op}"
        end
      end

      def build_order_by(sort)
        return nil if sort.nil? || sort.empty?

        sort.map { |s| "#{q(s[:field])} #{s[:ascending] ? "ASC" : "DESC"}" }.join(', ')
      end

      def build_where_clause(node)
        return nil if node.nil?

        case node
        when ConditionTreeBranch
          fragments = node.conditions.filter_map { |child| build_where_clause(child) }
          return nil if fragments.empty?

          joiner = node.aggregator.to_s.upcase == 'OR' ? ' OR ' : ' AND '
          "(#{fragments.join(joiner)})"
        when ConditionTreeLeaf
          translate_leaf(node)
        else
          raise ForestAdminDatasourceSnowflake::Error, "Unsupported condition tree node: #{node.class}"
        end
      end

      def translate_leaf(leaf)
        field = q(leaf.field)
        case leaf.operator
        when Operators::EQUAL                  then bind!(leaf.value)
                                                    "#{field} = ?"
        when Operators::NOT_EQUAL              then bind!(leaf.value)
                                                    "#{field} <> ?"
        when Operators::LESS_THAN              then bind!(leaf.value)
                                                    "#{field} < ?"
        when Operators::GREATER_THAN           then bind!(leaf.value)
                                                    "#{field} > ?"
        when Operators::LESS_THAN_OR_EQUAL     then bind!(leaf.value)
                                                    "#{field} <= ?"
        when Operators::GREATER_THAN_OR_EQUAL  then bind!(leaf.value)
                                                    "#{field} >= ?"
        when Operators::IN                     then translate_in(field, leaf.value)
        when Operators::NOT_IN                 then translate_in(field, leaf.value, negate: true)
        when Operators::PRESENT                then "#{field} IS NOT NULL"
        when Operators::MISSING                then "#{field} IS NULL"
        when Operators::BLANK                  then "(#{field} IS NULL OR #{field} = '')"
        when Operators::CONTAINS               then translate_like(field, "%#{leaf.value}%")
        when Operators::I_CONTAINS             then translate_ilike(field, "%#{leaf.value}%")
        when Operators::NOT_CONTAINS           then translate_like(field, "%#{leaf.value}%", negate: true)
        when Operators::NOT_I_CONTAINS         then translate_ilike(field, "%#{leaf.value}%", negate: true)
        when Operators::STARTS_WITH            then translate_like(field, "#{leaf.value}%")
        when Operators::I_STARTS_WITH          then translate_ilike(field, "#{leaf.value}%")
        when Operators::ENDS_WITH              then translate_like(field, "%#{leaf.value}")
        when Operators::I_ENDS_WITH            then translate_ilike(field, "%#{leaf.value}")
        when Operators::LIKE                   then translate_like(field, leaf.value)
        when Operators::I_LIKE                 then translate_ilike(field, leaf.value)
        when Operators::SHORTER_THAN           then bind!(leaf.value)
                                                    "LENGTH(#{field}) < ?"
        when Operators::LONGER_THAN            then bind!(leaf.value)
                                                    "LENGTH(#{field}) > ?"
        else
          raise ForestAdminDatasourceSnowflake::Error,
                "Unsupported operator '#{leaf.operator}' on field '#{leaf.field}'"
        end
      end

      def translate_in(quoted_field, values, negate: false)
        list = Array(values)
        return negate ? '1=1' : '1=0' if list.empty?

        placeholders = list.map do |v|
          bind!(v)
          '?'
        end.join(', ')
        "#{quoted_field} #{negate ? "NOT IN" : "IN"} (#{placeholders})"
      end

      def translate_like(quoted_field, value, negate: false)
        bind!(value)
        "#{quoted_field} #{negate ? "NOT LIKE" : "LIKE"} ?"
      end

      def translate_ilike(quoted_field, value, negate: false)
        bind!(value)
        "LOWER(#{quoted_field}) #{negate ? "NOT LIKE" : "LIKE"} LOWER(?)"
      end

      def bind!(value)
        @binds << value
      end
    end
  end
end
