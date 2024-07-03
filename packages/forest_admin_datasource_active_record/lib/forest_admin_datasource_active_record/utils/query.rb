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
        @select = []
      end

      def build
        build_select
        apply_filter
        apply_select
      end

      def get
        build

        return @query.all if @filter.page.nil?

        @query.offset(@filter.page.offset).limit(@filter.page.limit)
      end

      def apply_filter
        @query = apply_condition_tree(@filter.condition_tree) unless @filter.condition_tree.nil?
        @query = apply_sort(@filter.sort) unless @filter.sort.nil?

        @query
      end

      def apply_sort(sort)
        sort.each do |sort_clause|
          field = format_field(sort_clause[:field])
          @query = @query.order(field => sort_clause[:ascending] ? :asc : :desc)
        end

        @query
      end

      def apply_pagination(page)
        @query.offset(page.offset).limit(page.limit)

        @query
      end

      def apply_condition_tree(condition_tree, aggregator = nil)
        if condition_tree.is_a? Nodes::ConditionTreeBranch
          aggregator = condition_tree.aggregator.downcase.to_sym
          condition_tree.conditions.each do |condition|
            @query = apply_condition_tree(condition, aggregator)
            @query = @query.send(aggregator, @query)
          end

          @query
        else
          @query = compute_main_operator(condition_tree, aggregator || :and)
        end
      end

      def compute_main_operator(condition_tree, aggregator)
        field = format_field(condition_tree.field)
        value = condition_tree.value
        aggregator = aggregator.to_sym

        case condition_tree.operator
        when Operators::PRESENT
          @query = query_aggregator(aggregator, @collection.model.where.not({ field => nil }))
        when Operators::EQUAL, Operators::IN
          @query = query_aggregator(aggregator, @collection.model.where({ field => value }))
        when Operators::NOT_EQUAL, Operators::NOT_IN
          @query = query_aggregator(aggregator, @collection.model.where.not({ field => value }))
        when Operators::GREATER_THAN
          @query = query_aggregator(aggregator, @collection.model.where(@arel_table[field.to_sym].gt(value)))
        when Operators::LESS_THAN
          @query = query_aggregator(aggregator, @collection.model.where(@arel_table[field.to_sym].lt(value)))
        when Operators::NOT_CONTAINS
          @query = query_aggregator(aggregator,
                                    @collection.model.where.not(@arel_table[field.to_sym].matches("%#{value}%")))
        when Operators::LIKE
          @query = query_aggregator(aggregator, @collection.model.where(@arel_table[field.to_sym].matches(value)))
        when Operators::INCLUDES_ALL
          @query = query_aggregator(aggregator, @collection.model.where(@arel_table[field.to_sym].matches_all(value)))
        end

        @query
      end

      def build_select
        unless @projection.nil?
          @select += @projection.columns.map { |field| "#{@collection.model.table_name}.#{field}" }
          @projection.relations.each_key do |relation|
            relation_schema = @collection.schema[:fields][relation]
            @select << if relation_schema.type == 'OneToOne' || relation_schema.type == 'PolymorphicOneToOne'
                         "#{@collection.model.table_name}.#{relation_schema.origin_key_target}"
                       else
                         "#{@collection.model.table_name}.#{relation_schema.foreign_key}"
                       end
          end
        end

        @query
      end

      def apply_select
        unless @projection.nil?
          @query = @query.select(@select.join(', '))

          @query = @query.includes(format_relation_projection(@projection))
        end

        @query
      end

      def add_join_relation(relation_name)
        @query = @query.includes(relation_name.to_sym)

        @query
      end

      def format_field(field)
        @select << "#{@collection.model.table_name}.#{field}"

        if field.include?(':')
          relation_name, field = field.split(':')
          relation = @collection.schema[:fields][relation_name]
          table_name = @collection.datasource.get_collection(relation.foreign_collection).model.table_name
          add_join_relation(relation_name)
          @select << "#{table_name}.#{field}"

          return "#{table_name}.#{field}"
        end

        field
      end

      def query_aggregator(aggregator, query)
        if !@query.respond_to?(:where_clause) || @query.where_clause.empty?
          query
        else
          @query.send(aggregator, query)
        end
      end

      def format_relation_projection(projection)
        result = {}
        projection&.relations&.each do |relation, projection_relation|
          formatted_relations = format_relation_projection(projection_relation)

          result[relation.to_sym] = formatted_relations
        end
        result
      end
    end
  end
end
