module ForestAdminDatasourcePylon
  module Collections
    class BaseCollection < ForestAdminDatasourceToolkit::Collection
      ColumnSchema         = ForestAdminDatasourceToolkit::Schema::ColumnSchema
      Operators            = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
      Branch               = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
      Leaf                 = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
      ConditionTreeFactory = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::ConditionTreeFactory
      Equivalent           = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::ConditionTreeEquivalent
      SortFactory          = ForestAdminDatasourceToolkit::Components::Query::SortUtils::SortFactory

      # `residual` holds the conditions left over once the primary-key leaf has
      # been taken out of the tree, for the caller to apply in memory.
      IdLookup = Struct.new(:ids, :residual, keyword_init: true)

      # Mirrors the operators `ConditionTreeLeaf#match` evaluates natively; any
      # other operator needs an equivalence for the column's type to be
      # evaluable in memory.
      IN_MEMORY_OPERATORS = [Operators::IN, Operators::EQUAL, Operators::LESS_THAN, Operators::GREATER_THAN,
                             Operators::MATCH, Operators::STARTS_WITH, Operators::ENDS_WITH,
                             Operators::LONGER_THAN, Operators::SHORTER_THAN, Operators::INCLUDES_ALL,
                             Operators::NOT_IN, Operators::NOT_EQUAL, Operators::NOT_CONTAINS].freeze

      attr_reader :custom_fields

      # Template method: subclasses implement `define_schema` and
      # `define_relations` as hooks; ordering between them, custom-field
      # registration, and the search/count flags is owned here so collisions
      # are always evaluated against the final native schema.
      def initialize(datasource, name, custom_fields: [], searchable: false, countable: false, native_driver: nil)
        super(datasource, name, native_driver)
        define_schema
        define_relations
        @custom_fields = add_custom_fields(custom_fields)
        enable_search if searchable
        enable_count if countable
      end

      protected

      # Pylon has no `id` filter operator on /issues/search, so collections
      # short-circuit primary-key lookups to /resource/{id}. Ids are UUID
      # strings — unlike Zendesk, nothing has to be coerced to an integer.
      #
      # The leaf is also pulled out of a top-level AND, because Forest sends
      # `AND(id equal X, <scope>)` on a record detail as soon as a scope or a
      # segment is set, and `id` is not a field Pylon can filter on.
      def extract_id_lookup(node)
        ids = id_values(node)
        return IdLookup.new(ids: ids, residual: nil) if ids
        return nil unless and_branch?(node)

        conditions = Array(node.conditions)
        id_index = conditions.index { |condition| id_values(condition) }
        return nil if id_index.nil?

        residual = ConditionTreeFactory.intersect(conditions.reject.with_index { |_, index| index == id_index })
        ensure_residual_appliable!(residual)
        IdLookup.new(ids: id_values(conditions[id_index]), residual: residual)
      end

      def build_pylon_filter(caller, filter)
        Query::ConditionTreeTranslator.call(filter&.condition_tree,
                                            api_filters: api_filters,
                                            timezone: timezone_for(caller))
      end

      # Overridden by collections whose endpoint can filter server-side.
      def api_filters
        {}
      end

      # An unknown field silently disables sorting: a Pylon endpoint only honours
      # the fixed allow-list its collection declares.
      def translate_sort(sort, allow_list)
        return [nil, nil] if sort.nil? || sort.empty?

        field, ascending = sort_field_and_direction(sort.first)
        pylon_field = allow_list[field.to_s]
        return [nil, nil] unless pylon_field

        [pylon_field, ascending ? 'asc' : 'desc']
      end

      # The agent injects an ascending primary-key sort whenever the request
      # asks for no order, so the default cannot be told apart from a chosen
      # order by presence alone.
      def default_pk_sort?(sort)
        normalized_sort_clauses(sort) == normalized_sort_clauses(SortFactory.by_primary_keys(self))
      end

      def timezone_for(caller)
        return 'UTC' unless caller.respond_to?(:timezone)

        timezone = caller.timezone
        timezone.nil? || timezone.to_s.empty? ? 'UTC' : timezone
      end

      def project(record, projection)
        return record if projection.nil?

        wanted = Array(projection).map(&:to_s).reject { |p| p.include?(':') }
        return record if wanted.empty?

        wanted.to_h { |k| [k, record[k]] }
      end

      def translate_page(page)
        return [0, Client::MAX_SEARCH_LIMIT] if page.nil?

        limit = page.limit.to_i.positive? ? page.limit.to_i : Client::MAX_SEARCH_LIMIT
        [page.offset.to_i.clamp(0, nil), limit]
      end

      # Adds custom fields, skipping any whose column name collides with a
      # field already declared on the collection, and clamping the declared
      # operators to those the API accepts on a custom field — so the schema
      # never advertises a filter the translator would then refuse. Returns
      # the subset actually added, carrying the clamped schemas, so callers
      # can keep their serializer and api_filters in sync with the schema.
      def add_custom_fields(custom_fields)
        custom_fields.filter_map do |cf|
          column_name = cf[:column_name]
          if schema[:fields].key?(column_name)
            ForestAdminDatasourcePylon.logger.warn(
              "[forest_admin_datasource_pylon] Custom field '#{column_name}' on collection " \
              "'#{name}' conflicts with an existing field; skipping."
            )
            nil
          else
            clamped = clamp_custom_field_operators(column_name, cf[:schema])
            add_field(column_name, clamped)
            cf.merge(schema: clamped)
          end
        end
      end

      # Operators a custom field may advertise. The empty default matches the
      # empty `api_filters`: a collection that filters nothing server-side
      # must not advertise custom-field filters either.
      def allowed_custom_field_operators
        []
      end

      private

      def define_schema    = raise(NotImplementedError, "#{self.class} did not implement define_schema")
      def define_relations = raise(NotImplementedError, "#{self.class} did not implement define_relations")

      def id_values(node)
        return nil unless node.is_a?(Leaf) && node.field == 'id'
        return nil unless [Operators::EQUAL, Operators::IN].include?(node.operator)

        Array(node.value).map(&:to_s).reject(&:empty?)
      end

      def and_branch?(node)
        node.is_a?(Branch) && node.aggregator.to_s.casecmp('and').zero?
      end

      def clamp_custom_field_operators(column_name, schema)
        declared = Array(schema.filter_operators)
        dropped  = declared - allowed_custom_field_operators
        return schema if dropped.empty?

        ForestAdminDatasourcePylon.logger.warn(
          "[forest_admin_datasource_pylon] Custom field '#{column_name}' on collection '#{name}' declares " \
          "operators the API cannot honour on a custom field (#{dropped.join(", ")}); they are not advertised."
        )
        schema.dup.tap { |clamped| clamped.filter_operators = declared - dropped }
      end

      # A residual is evaluated by `ConditionTree#apply`, which compares scalar
      # values: a Json column holds a list whose Pylon membership semantics
      # have no in-memory counterpart, and an operator without an equivalence
      # for the column's type has no in-memory evaluation at all. Both would
      # silently corrupt the lookup's result, so they are refused instead.
      def ensure_residual_appliable!(node)
        case node
        when Branch then node.conditions.each { |condition| ensure_residual_appliable!(condition) }
        when Leaf   then raise_unappliable_residual(node) unless residual_leaf_appliable?(node)
        end
      end

      def residual_leaf_appliable?(leaf)
        column = schema[:fields][leaf.field]
        return false if column.nil? || column.column_type == 'Json'

        Equivalent.equivalent_tree?(leaf.operator, IN_MEMORY_OPERATORS, column.column_type)
      end

      def raise_unappliable_residual(leaf)
        raise UnsupportedOperatorError,
              "Operator '#{leaf.operator}' on field '#{leaf.field}' cannot be combined with a primary-key " \
              'lookup: Pylon cannot filter on id server-side, so the other conditions run in memory, ' \
              'which this one does not support.'
      end

      def sort_field_and_direction(entry)
        return [entry.field, entry.ascending] if entry.respond_to?(:field)

        field     = entry.key?(:field)     ? entry[:field]     : entry['field']
        ascending = entry.key?(:ascending) ? entry[:ascending] : entry['ascending']
        [field, ascending]
      end

      def normalized_sort_clauses(sort)
        Array(sort).map do |entry|
          field, ascending = sort_field_and_direction(entry)
          [field.to_s, ascending]
        end
      end
    end
  end
end
