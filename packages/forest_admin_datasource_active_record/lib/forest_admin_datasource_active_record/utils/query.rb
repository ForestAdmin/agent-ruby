require 'set'

module ForestAdminDatasourceActiveRecord
  module Utils
    class Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      attr_reader :query, :select, :joined_relations

      def initialize(collection, projection, filter)
        @collection = collection
        @query = @collection.model.unscoped
        @projection = projection
        @filter = filter
        @arel_table = @collection.model.arel_table
        @select = []
        # relation path (e.g. "bank_account.organizations_view") => { columns: { col => sql_alias }, pk_alias: }
        @joined_relations = {}
        @alias_counter = 0
        # tables already joined by filters/sorts, so apply_select does not join them a second time
        @filter_joined_tables = Set.new
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
              # foreign_key is an array for a composite-key belongs_to through hop
              Array(root_through_foreign_key(collection, relation_name)).each do |through_fk|
                @select << "#{collection.model.table_name}.#{through_fk}"
              end
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
        unless @projection.nil?
          join_tree, preload_tree = split_relations

          @query = @query.left_outer_joins(join_tree) unless join_tree.empty?
          @query = @query.includes(preload_tree) unless preload_tree.empty?
        end
        @query = @query.select(@select.join(', ')) if @select

        @query
      end

      def split_relations
        join_tree = {}
        preload_tree = {}
        used_tables = Set[@collection.model.table_name] | @filter_joined_tables

        @projection.relations.each do |relation_name, sub_projection|
          tables = joinable_tables(@collection, relation_name, sub_projection, used_tables)
          if tables
            used_tables |= tables
            join_tree[relation_name.to_sym] = format_relation_projection(sub_projection)
            collect_joined_selects(@collection, relation_name, sub_projection, [relation_name])
          else
            preload_tree[relation_name.to_sym] = format_relation_projection(sub_projection)
          end
        end

        [join_tree, preload_tree]
      end

      def collect_joined_selects(collection, relation_name, sub_projection, path)
        relation_schema = collection.schema[:fields][relation_name]
        target = local_ar_collection(collection.datasource, relation_schema.foreign_collection)
        table = target.model.table_name
        pk_columns = Array(target.model.primary_key) # array for composite primary keys

        alias_map = {}
        # a pk column is always selected so the serializer can detect a NULL (absent) left-joined relation
        target.model.connection_pool.with_connection do |connection|
          (sub_projection.columns + pk_columns).uniq.each do |column|
            sql_alias = next_join_alias
            # quote via the adapter so identifiers are valid on every database (e.g. backticks on MySQL)
            @select << "#{connection.quote_table_name(table)}.#{connection.quote_column_name(column)} " \
                       "AS #{connection.quote_column_name(sql_alias)}"
            alias_map[column] = sql_alias
          end
        end
        @joined_relations[path.join('.')] = { columns: alias_map, pk_alias: alias_map[pk_columns.first] }

        sub_projection.relations.each do |nested_name, nested_projection|
          collect_joined_selects(target, nested_name, nested_projection, path + [nested_name])
        end
      end

      def next_join_alias
        @alias_counter += 1
        "fa_join_#{@alias_counter}"
      end

      # Set of tables the subtree adds via JOIN, or nil if any relation in it can't be safely joined.
      def joinable_tables(collection, relation_name, sub_projection, used_tables)
        target = joinable_target(collection, relation_name, used_tables)
        return nil if target.nil?

        tables = Set[target.model.table_name] | through_tables(collection, relation_name)
        sub_projection.relations.each do |nested_name, nested_projection|
          nested = joinable_tables(target, nested_name, nested_projection, used_tables | tables)
          return nil if nested.nil?

          tables |= nested
        end
        tables
      end

      # The target collection when this hop is safe to collapse into a JOIN, else nil (-> preload).
      def joinable_target(collection, relation_name, used_tables)
        relation_schema = collection.schema[:fields][relation_name]
        return unless relation_schema.respond_to?(:foreign_collection)

        # a scoped association applies its scope to the JOIN and may inject raw/unqualified SQL or
        # extra joins (e.g. `belongs_to :x, -> { where('id > ?', 1) }`)
        reflection = collection.model.reflect_on_association(relation_name.to_sym)
        return if reflection.nil? || reflection.scope

        case relation_schema.type
        when 'ManyToOne' then nil
        when 'OneToOne' then return unless belongs_to_chain_through?(reflection)
        else return
        end

        target = local_ar_collection(collection.datasource, relation_schema.foreign_collection)
        return if target.nil? || !target.model.default_scopes.empty? # same risk as a scoped association
        return unless same_database?(collection.model, target.model)
        return if used_tables.include?(target.model.table_name) # a table joined twice would be aliased by AR
        return if through_tables(collection, relation_name).intersect?(used_tables)

        target
      end

      def through_tables(collection, relation_name)
        through = collection.model.reflect_on_association(relation_name.to_sym)&.through_reflection
        return Set[] unless through

        Set[through.table_name]
      rescue StandardError
        Set[]
      end

      def belongs_to_chain_through?(reflection)
        return false unless reflection.through_reflection?

        through = reflection.through_reflection
        source = reflection.source_reflection

        through && source && through.belongs_to? && source.belongs_to? &&
          through.scope.nil? && source.scope.nil? && through.klass.default_scopes.empty? &&
          same_database?(reflection.active_record, through.klass)
      rescue StandardError
        false
      end

      def same_database?(model_a, model_b)
        # compare the pools, not connection_specification_name (only an owner class name, shared across shards)
        model_a.connection_pool == model_b.connection_pool
      rescue StandardError
        false
      end

      # The target collection only if it is AR-backed AND belongs to this exact datasource, else nil.
      # Guards (concrete class + identity, not just the name) against a foreign-datasource collection.
      def local_ar_collection(datasource, name)
        collection = datasource.get_collection(name)
        return nil unless collection.is_a?(ForestAdminDatasourceActiveRecord::Collection)
        return nil unless collection.datasource.equal?(datasource)

        collection
      rescue StandardError
        nil
      end

      def add_join_relation(relation_name)
        @query = @query.left_joins(relation_name.to_sym)

        @query
      end

      def root_through_foreign_key(collection, relation_name)
        through = collection.model.reflect_on_association(relation_name.to_sym)&.through_reflection
        return unless through&.belongs_to?

        through.foreign_key
      rescue StandardError
        nil
      end

      def resolve_field(original_field)
        if original_field.include?(':')
          relation_name, column_name = original_field.split(':')
          relation = @collection.schema[:fields][relation_name]
          related_collection = @collection.datasource.get_collection(relation.foreign_collection)
          add_join_relation(relation_name)
          @filter_joined_tables << related_collection.model.table_name

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
          # Preserve includes and joins from @query when replacing with new query
          query = query.includes(@query.includes_values) if @query.includes_values.any?
          query = query.left_joins(*@query.left_outer_joins_values) if @query.left_outer_joins_values.any?
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
