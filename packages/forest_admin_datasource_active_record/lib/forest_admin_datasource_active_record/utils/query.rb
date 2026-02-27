module ForestAdminDatasourceActiveRecord
  module Utils
    class Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      attr_reader :query, :select

      def initialize(collection, projection, filter)
        @collection = collection
        @query = @collection.model.unscoped
        @projection = projection
        @filter = filter
        @arel_table = @collection.model.arel_table
        @select = []
      end

      def build
        build_select(@collection, @projection)
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
          resolved = resolve_field(sort_clause[:field])
          @query = @query.order(resolved[:formatted] => sort_clause[:ascending] ? :asc : :desc)
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
        resolved = resolve_field(condition_tree.field)
        field = resolved[:formatted]
        arel_attr = resolved[:arel_attr]
        value = condition_tree.value
        aggregator = aggregator.to_sym

        case condition_tree.operator
        when Operators::PRESENT
          field_schema = ForestAdminDatasourceToolkit::Utils::Collection.get_field_schema(@collection,
                                                                                          condition_tree.field)
          @query = if field_schema.column_type == 'String'
                     query_aggregator(aggregator, @collection.model.where.not({ field => [nil, ''] }))
                   else
                     query_aggregator(aggregator, @collection.model.where.not({ field => nil }))
                   end
        when Operators::BLANK
          field_schema = ForestAdminDatasourceToolkit::Utils::Collection.get_field_schema(@collection,
                                                                                          condition_tree.field)
          @query = if field_schema.column_type == 'String'
                     query_aggregator(aggregator, @collection.model.where({ field => [nil, ''] }))
                   else
                     query_aggregator(aggregator, @collection.model.where({ field => nil }))
                   end
        when Operators::MISSING
          @query = query_aggregator(aggregator, @collection.model.where({ field => nil }))
        when Operators::EQUAL, Operators::IN
          @query = query_aggregator(aggregator, @collection.model.where({ field => value }))
        when Operators::NOT_EQUAL, Operators::NOT_IN
          @query = query_aggregator(aggregator, @collection.model.where.not({ field => value }))
        when Operators::GREATER_THAN
          @query = query_aggregator(aggregator, build_comparison_query(condition_tree.field, arel_attr, value, :gt))
        when Operators::GREATER_THAN_OR_EQUAL
          @query = query_aggregator(aggregator, build_comparison_query(condition_tree.field, arel_attr, value, :gteq))
        when Operators::LESS_THAN
          @query = query_aggregator(aggregator, build_comparison_query(condition_tree.field, arel_attr, value, :lt))
        when Operators::LESS_THAN_OR_EQUAL
          @query = query_aggregator(aggregator, build_comparison_query(condition_tree.field, arel_attr, value, :lteq))
        when Operators::CONTAINS
          @query = query_aggregator(aggregator,
                                    @collection.model.where(arel_attr.matches("%#{value}%")))
        when Operators::I_CONTAINS
          lower_field = Arel::Nodes::NamedFunction.new('LOWER', [arel_attr])
          @query = query_aggregator(aggregator,
                                    @collection.model.where(lower_field.matches("%#{value.to_s.downcase}%")))
        when Operators::NOT_CONTAINS
          @query = query_aggregator(aggregator,
                                    @collection.model.where.not(arel_attr.matches("%#{value}%")))
        when Operators::NOT_I_CONTAINS
          lower_field = Arel::Nodes::NamedFunction.new('LOWER', [arel_attr])
          @query = query_aggregator(aggregator,
                                    @collection.model.where.not(lower_field.matches("%#{value.to_s.downcase}%")))
        when Operators::STARTS_WITH
          @query = query_aggregator(aggregator,
                                    @collection.model.where(arel_attr.matches("#{value}%")))
        when Operators::I_STARTS_WITH
          lower_field = Arel::Nodes::NamedFunction.new('LOWER', [arel_attr])
          @query = query_aggregator(aggregator,
                                    @collection.model.where(lower_field.matches("#{value.to_s.downcase}%")))
        when Operators::ENDS_WITH
          @query = query_aggregator(aggregator,
                                    @collection.model.where(arel_attr.matches("%#{value}")))
        when Operators::I_ENDS_WITH
          lower_field = Arel::Nodes::NamedFunction.new('LOWER', [arel_attr])
          @query = query_aggregator(aggregator,
                                    @collection.model.where(lower_field.matches("%#{value.to_s.downcase}")))
        when Operators::LIKE
          @query = query_aggregator(aggregator, @collection.model.where(arel_attr.matches(value)))
        when Operators::I_LIKE
          lower_field = Arel::Nodes::NamedFunction.new('LOWER', [arel_attr])
          @query = query_aggregator(aggregator,
                                    @collection.model.where(lower_field.matches(value.to_s.downcase)))
        when Operators::MATCH
          # Match operator supports:
          # - Regexp objects from pattern transformations: Regexp.new("pattern")
          # - JavaScript regex strings from comparison transformations: "/(pattern)/g"
          pattern = if value.is_a?(Regexp)
                      value.source
                    elsif (match = value.to_s.match(%r{^/(.+)/[gim]*$}))
                      match[1]
                    else
                      value.to_s
                    end

          # Use database-specific regex syntax
          adapter_name = @collection.model.connection_pool.db_config.adapter.downcase
          table_and_column = "#{arel_attr.relation.name}.#{arel_attr.name}"
          regex_clause = case adapter_name
                         when 'postgresql'
                           "#{table_and_column} ~ ?"
                         when 'mysql2', 'mysql', 'sqlite', 'sqlite3'
                           "#{table_and_column} REGEXP ?"
                         else
                           raise ArgumentError, "Match operator is not supported for database adapter '#{adapter_name}'"
                         end

          @query = query_aggregator(aggregator, @collection.model.where(regex_clause, pattern))
        when Operators::INCLUDES_ALL
          @query = query_aggregator(aggregator, @collection.model.where(arel_attr.matches_all(value)))
        when Operators::SHORTER_THAN
          length_func = Arel::Nodes::NamedFunction.new('LENGTH', [arel_attr])
          @query = query_aggregator(aggregator, @collection.model.where(length_func.lt(value)))
        when Operators::LONGER_THAN
          length_func = Arel::Nodes::NamedFunction.new('LENGTH', [arel_attr])
          @query = query_aggregator(aggregator, @collection.model.where(length_func.gt(value)))
        end

        @query
      end

      def build_select(collection, projection)
        return if projection.nil?

        if collection.model.table_name == @collection.model.table_name
          @select += projection.columns.map { |field| "#{collection.model.table_name}.#{field}" }
        end

        one_to_one_relations = %w[OneToOne PolymorphicOneToOne]
        many_to_one_relations = %w[ManyToOne PolymorphicManyToOne]

        projection.relations.each do |relation_name, sub_projection|
          relation_schema = collection.schema[:fields][relation_name]
          if collection.model.table_name == @collection.model.table_name
            if one_to_one_relations.include?(relation_schema.type)
              @select << "#{collection.model.table_name}.#{relation_schema.origin_key_target}"
            elsif many_to_one_relations.include?(relation_schema.type)
              @select << "#{collection.model.table_name}.#{relation_schema.foreign_key}"
            end
          end

          next if relation_schema.type == 'PolymorphicManyToOne'

          if relation_schema.respond_to?(:foreign_collection)
            target_collection = collection.datasource.get_collection(relation_schema.foreign_collection)
            build_select(target_collection, sub_projection)
          end
        end
      end

      def apply_select
        @query = @query.select(@select.join(', ')) if @select
        @query = @query.includes(format_relation_projection(@projection)) unless @projection.nil?

        @query
      end

      def add_join_relation(relation_name)
        @query = @query.includes(relation_name.to_sym)

        @query
      end

      def resolve_field(original_field)
        if original_field.include?(':')
          relation_name, column_name = original_field.split(':')
          relation = @collection.schema[:fields][relation_name]
          related_collection = @collection.datasource.get_collection(relation.foreign_collection)
          add_join_relation(relation_name)

          {
            formatted: "#{related_collection.model.table_name}.#{column_name}",
            arel_attr: related_collection.model.arel_table[column_name.to_sym]
          }
        else
          {
            formatted: original_field,
            arel_attr: @arel_table[original_field.to_sym]
          }
        end
      end

      def build_comparison_query(original_field, arel_attr, value, operator)
        # When comparing a String field with a numeric value, compare the length of the string
        # Otherwise, do a lexicographic comparison
        if value.is_a?(Numeric)
          field_schema = ForestAdminDatasourceToolkit::Utils::Collection.get_field_schema(@collection, original_field)
          if field_schema.column_type == 'String'
            length_func = Arel::Nodes::NamedFunction.new('LENGTH', [arel_attr])
            return @collection.model.where(length_func.send(operator, value))
          end
        end

        @collection.model.where(arel_attr.send(operator, value))
      end

      def query_aggregator(aggregator, query)
        if !@query.respond_to?(:where_clause) || @query.where_clause.empty?
          # Preserve includes from @query when replacing with new query
          query = query.includes(@query.includes_values) if @query.includes_values.any?
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
