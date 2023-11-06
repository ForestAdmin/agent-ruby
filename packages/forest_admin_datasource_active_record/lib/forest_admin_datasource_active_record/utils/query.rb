module ForestAdminDatasourceActiveRecord
  module Utils
    class Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      def initialize(collection, projection, filter)
        @collection = collection
        @query = @collection.model
        @projection = projection
        @filter = filter
        @arel_table = @collection.model.arel_table
      end

      def build
        @query = select
        @query = apply_filter

        @query
      end

      def apply_filter
        @query = apply_condition_tree(@filter.condition_tree) unless @filter.condition_tree.nil?
        @query = apply_pagination(@filter.page) unless @filter.page.nil?

        @query
      end

      def apply_pagination(page)
        @query.offset(page.offset).limit(page.limit)

        @query
      end

      def apply_condition_tree(condition_tree, aggregator = nil)
        if condition_tree.is_a? Nodes::ConditionTreeBranch
          aggregator = condition_tree.aggregator.downcase
          condition_tree.conditions.each do |condition|
            @query = @query.send(aggregator, apply_condition_tree(condition, aggregator))
          end
          @query
        else
          compute_main_operator(condition_tree, aggregator || 'and')
        end
      end

      def compute_main_operator(condition_tree, aggregator)
        field = condition_tree.field
        value = condition_tree.value

        case condition_tree.operator
        when Operators::PRESENT
          @query = @query.send(aggregator, @query.where.not({ field => nil }))
        when Operators::EQUAL, Operators::IN
          @query = @query.send(aggregator, @query.where({ field => value }))
        when Operators::NOT_EQUAL, Operators::NOT_IN
          @query = @query.send(aggregator, @query.where.not({ field => value }))
        when Operators::GREATER_THAN
          @query = @query.send(aggregator, @query.where(@arel_table[field.to_sym].gt(value)))
        when Operators::LESS_THAN
          @query = @query.send(aggregator, @query.where(@arel_table[field.to_sym].lt(value)))
        when Operators::NOT_CONTAINS
          @query = @query.send(aggregator, @query.where.not(@arel_table[field.to_sym].matches("%#{value}%")))
        when Operators::CONTAINS
          @query = @query.send(aggregator, @query.where(@arel_table[field.to_sym].matches("%#{value}%")))
        when Operators::INCLUDES_ALL
          # TODO: to implement
        end

        @query
      end

      def select
        unless @projection.nil?
          query_select = @projection.columns.map { |field| "#{@collection.model.table_name}.#{field}" }
          @projection.relations.each do |relation, _fields|
            relation_schema = @collection.fields[relation]
            if relation_schema.type == 'OneToOne'
              query_select.push("#{@collection.model.table_name}.#{relation_schema.origin_key_target}")
            else
              query_select.push("#{@collection.model.table_name}.#{relation_schema.foreign_key}")
            end
          end

          @query = @query.select(query_select.join(', '))
          @query = @query.eager_load(@projection.relations.keys.map(&:to_sym))
          # TODO: replace eager_load by joins because eager_load select ALL columns of relation
          # @query = @query.joins(@projection.relations.keys.map(&:to_sym))
        end

        @query
      end
    end
  end
end
