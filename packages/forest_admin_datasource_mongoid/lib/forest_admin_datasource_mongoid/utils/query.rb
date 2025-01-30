module ForestAdminDatasourceMongoid
  module Utils
    class Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      attr_reader :query

      def initialize(collection, projection, filter)
        @collection = collection
        @query = @collection.model.unscoped
        @projection = projection
        @filter = filter
        @select = []
        @virtual_joins = {}
      end

      def build
        build_select
        apply_filter
        apply_select
      end

      def get
        build
        return @query.all if @filter.page.nil?

        @query.skip(@filter.page.offset).limit(@filter.page.limit)
      end

      def apply_filter
        @query = apply_condition_tree(@filter.condition_tree) unless @filter.condition_tree.nil?
        @query = apply_referenced_relations
        @query = apply_sort(@filter.sort) unless @filter.sort.nil?

        @query
      end

      def apply_referenced_relations
        @virtual_joins.each do |relation_name, match|
          relation = @collection.schema[:fields][relation_name]
          if relation.type == 'OneToOne'
            @query = @query.in(relation.origin_key_target => match.distinct(relation.origin_key))
          elsif relation.type == 'ManyToOne'
            @query = @query.in(relation.foreign_key => match.distinct(relation.foreign_key_target))
          end
        end
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
          end
        elsif referenced_relation?(condition_tree.field)
          relation_name, field_name = condition_tree.field.split(':')
          relation = @collection.model.relations[relation_name]
          @virtual_joins[relation_name] = relation.klass.unscoped unless @virtual_joins[relation_name]
          @virtual_joins[relation_name] = compute_main_operator(
            @virtual_joins[relation_name],
            condition_tree.override(field: field_name),
            aggregator || :and
          )
        else
          @query = compute_main_operator(@query, condition_tree, aggregator || :and)
        end

        @query
      end

      def compute_main_operator(query, condition_tree, aggregator)
        field = format_field(condition_tree.field)
        value = condition_tree.value
        aggregator = aggregator.to_sym

        case condition_tree.operator
        when Operators::PRESENT
          query = query.send(aggregator, @collection.model.not.where(field => nil))
        when Operators::EQUAL
          query = query.send(aggregator, @collection.model.where(field => value))
        when Operators::IN
          query = query.send(aggregator, @collection.model.in(field => value))
        when Operators::NOT_EQUAL
          query = query.send(aggregator, @collection.model.not.where(field => value))
        when Operators::NOT_IN
          query = query.send(aggregator, @collection.model.not.in(field => value))
        when Operators::GREATER_THAN
          query = query.send(aggregator, @collection.model.where(field => { '$gt' => value }))
        when Operators::LESS_THAN
          query = query.send(aggregator, @collection.model.where(field => { '$lt' => value }))
        when Operators::NOT_CONTAINS
          query = query.send(aggregator, @collection.model.not.where(field => Regexp.new("^.*#{value}.*$")))
        when Operators::NOT_I_CONTAINS
          query = query.send(aggregator, @collection.model.not.where(field => Regexp.new("^.*#{value}.*$", 'i')))
        when Operators::MATCH
          query = query.send(aggregator, @collection.model.where(field => { '$regex' => value }))
        when Operators::INCLUDES_ALL
          query = query.send(aggregator, @collection.model.where(field => { '$all' => value }))
        end

        query
      end

      def referenced_relation?(path)
        return false unless path.include?(':')

        relation_name, = path.split(':')

        @collection.model.relations.key?(relation_name) &&
          !@collection.model.relations[relation_name].embedded?
      end

      def build_select
        return if @projection.nil?

        @select = @projection.columns
        @projection.relations.each_key do |relation|
          relation_schema = @collection.schema[:fields][relation]
          @select << if %w[OneToOne PolymorphicOneToOne].include?(relation_schema.type)
                       "#{@collection.model.collection_name}.#{relation_schema.origin_key_target}"
                     else
                       "#{@collection.model.collection_name}.#{relation_schema.foreign_key}"
                     end
        end
      end

      def apply_select
        @query = @query.only(@select) if @select
        @query = @query.includes(format_relation_projection(@projection)) unless @projection.nil?

        @query
      end

      def format_field(field)
        field.tr(':', '.')
      end

      def format_relation_projection(projection)
        result = []
        projection&.relations&.each_value do |projection_relation|
          formatted_relations = format_relation_projection(projection_relation)
          result += formatted_relations
        end

        result
      end
    end
  end
end
