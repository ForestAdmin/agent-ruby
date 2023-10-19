module ForestAdminDatasourceActiveRecord
  module Utils
    class Query
      def initialize(collection, projection, filter)
        @collection = collection
        @query = @collection.model
        @projection = projection
        @filter = filter
      end

      def build
        @query = select
        @query = apply_filter

        @query
      end

      def apply_filter
        @query = apply_condition_tree(@filter.condition_tree) unless @filter.condition_tree.nil?

        @query
      end

      def apply_condition_tree(condition_tree, aggregator = nil)
        # if condition_tree.is_a ConditionTreeBranch
        # TODO: add for ConditionTreeBranch
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

        @query
      end

      def select
        if !@projection.nil?
          query_select = @projection.columns.map { |field| "#{@collection.model.table_name}.#{field}" }.join(', ')

          @projection.relations.each do |relation, _fields|
            relation_schema = @collection.fields[relation]
            query_select += ", #{@collection.model.table_name}.#{relation_schema.foreign_key}"
            # fields.each { |field| query_select += ", #{relation_table}.#{field}" }
          end

          @query = @query.select(query_select)
          @query = @query.eager_load(@projection.relations.keys.map(&:to_sym))
          # TODO: replace eager_load by joins because eager_load select ALL columns of relation
          # @query = @query.joins(@projection.relations.keys.map(&:to_sym))
        end

        @query
      end
    end
  end
end
