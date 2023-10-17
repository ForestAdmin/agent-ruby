module ForestAdminDatasourceActiveRecord
  module Utils
    class Query
      def initialize(model, projection, filter)
        @query = model
        @projection = projection
        @filter = filter
      end

      def build
        @query = select
        @query = apply_filter

        return @query
      end

      def apply_filter
        @query = apply_condition_tree(@filter.condition_tree) unless @filter.condition_tree.nil?

        return @query
      end

      def apply_condition_tree(condition_tree, aggregator = nil)
        # if condition_tree.is_a ConditionTreeBranch
          #TODO: add for ConditionTreeBranch
        # else
          compute_main_operator(condition_tree, aggregator || 'and')
        # end
      end

      def compute_main_operator(condition_tree, aggregator)
        field = condition_tree.field
        value = condition_tree.value
        case condition_tree.operator
        when 'EQUAL'
          @query = @query.send(aggregator, @query.where({ field => value }))
        end

        return @query
      end

      def select
        query_select = @projection.columns.join(', ')

        @projection.relations.each do |relation, fields|
          relation_table = datasource.collection(relation).model.table_name
          fields.each { |field| query += ", #{relation_table}.#{field}" }
        end

        @query = @query.select(query_select)
        @query = @query.joins(@projection.relations.keys.map(&:to_sym))
      end
    end
  end
end
