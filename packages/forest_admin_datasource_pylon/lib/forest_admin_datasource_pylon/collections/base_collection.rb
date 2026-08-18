module ForestAdminDatasourcePylon
  module Collections
    class BaseCollection < ForestAdminDatasourceToolkit::Collection
      ColumnSchema         = ForestAdminDatasourceToolkit::Schema::ColumnSchema
      ManyToOneSchema      = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema
      OneToManySchema      = ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema
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

      # The operators `ConditionTreeLeaf#match` evaluates by dereferencing the
      # column value without a nil guard, unlike the string operators which all
      # test `is_a?(String)` first. They need the guard added here.
      NIL_UNSAFE_OPERATORS = [Operators::LESS_THAN, Operators::GREATER_THAN, Operators::INCLUDES_ALL].freeze

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

      # How a collection another one points at with a ManyToOne is read in bulk:
      # the serialized records of `ids`, indexed by id, missing ids left out.
      #
      # Public because the caller is the pointing collection, a different object:
      # going through the collection rather than through the client is what keeps
      # a related record serialized by the collection owning its shape, instead
      # of by a second field list kept in the embedder.
      def records_indexed_by_id(_ids)
        raise NotImplementedError, "#{self.class} did not implement records_indexed_by_id"
      end

      # Pylon exposes no aggregate endpoint, and the pages of a cursor walk are
      # not the dataset: a count or a group computed over them would look exact
      # while answering a fraction. Every column is registered with
      # `is_groupable: false` so the UI never offers one, and a chart built
      # through the API anyway is refused here rather than through the
      # contract's NotImplementedError, which reads as an oversight.
      #
      # FetchAllCollection, which does hold every record Pylon has, overrides
      # this and answers exactly.
      def aggregate(_caller, _filter, _aggregation, _limit = nil)
        raise UnsupportedOperatorError,
              "#{name} cannot be aggregated: Pylon exposes no aggregate endpoint, and counting or grouping the " \
              'pages the agent walked would answer a fraction of the collection as if it were the whole of it.'
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
        ensure_no_relation_leaf!(node)
        ids = id_values(node)
        return IdLookup.new(ids: ids, residual: nil) if ids
        return nil unless and_branch?(node)

        conditions = Array(node.conditions)
        id_index = conditions.index { |condition| id_values(condition) }
        return nil if id_index.nil?

        residual = ConditionTreeFactory.intersect(conditions.reject.with_index { |_, index| index == id_index })
        ensure_residual_appliable!(residual)
        IdLookup.new(ids: id_values(conditions[id_index]), residual: guard_nil_comparisons(residual))
      end

      # Pylon runs the free-text search inside its search endpoint, which the
      # primary-key short-circuit does not go through, and neither the fields it
      # covers nor its fuzziness can be reproduced in memory. Answering with the
      # unsearched record would be the very thing this datasource refuses: a
      # result that looks filtered and is not.
      def ensure_searchless_lookup!(filter)
        search = filter&.search
        return if search.nil? || search.to_s.strip.empty?

        raise UnsupportedOperatorError,
              "A search cannot be combined with a filter on 'id': Pylon searches through its search endpoint, " \
              'which cannot filter on id, while an id is read through its own endpoint, which cannot search. ' \
              'Clear the search or drop the id condition.'
      end

      # Forest asks for an offset/limit window, Pylon hands out cursor pages: the
      # walker bridges the two, `search_page` performs one call, and the records
      # it collected are serialized by the collection.
      def search_records(caller, filter)
        pylon_filter  = build_pylon_filter(caller, filter)
        search_text   = filter&.search
        offset, limit = translate_page(filter&.page)

        records = walker.walk(offset: offset, limit: limit) do |batch, cursor|
          search_page(limit: batch, cursor: cursor, filter: pylon_filter, search_text: search_text)
        end
        records.map { |record| serialize(record) }
      end

      # One page of the walk, as a Client::SearchPage: the endpoint and its
      # parameter names belong to the collection, the walk does not.
      def search_page(limit:, cursor:, filter:, search_text:)
        raise NotImplementedError, "#{self.class} did not implement search_page"
      end

      # Sliced after the lookup, not before, so ids that resolved to nothing
      # (404) do not eat into the requested window.
      def page_window(records, filter)
        offset, limit = translate_page(filter&.page)
        records[offset, limit] || []
      end

      def build_pylon_filter(caller, filter)
        tree = filter&.condition_tree
        ensure_no_relation_leaf!(tree)
        ensure_no_stray_id!(tree)
        Query::ConditionTreeTranslator.call(tree, api_filters: api_filters, timezone: timezone_for(caller))
      end

      # The `ApiFilters` module of the collection, whose table is the single
      # source of truth for what its endpoint filters. The empty table is the
      # default: a collection read whole and filtered in memory filters nothing
      # server-side.
      def filter_table = Query::OperatorMaps::EmptyTable

      # What the endpoint filters server-side: the table of the collection, plus
      # one entry per custom field — filtered through the very Pylon slug it is
      # read by, with the operators the integrator declared on the column.
      def api_filters
        @api_filters ||= custom_fields.each_with_object(filter_table::API_FILTERS.dup) do |cf, filters|
          filters[cf[:column_name]] = filter_table.for_custom_field(cf[:schema])
        end
      end

      # A native column: read-only in this story — writes land in a later one —
      # and never groupable, as no Pylon endpoint aggregates. It is not sortable
      # either, the ColumnSchema default, because no search endpoint takes a sort
      # parameter. Filter operators are not chosen here: they come from
      # `filter_table`, which mirrors the allow-list of the API, so a column
      # missing from it gets none and the UI offers no filter Pylon would refuse.
      def add_column(name, type, is_primary_key: false)
        add_field(name, ColumnSchema.new(column_type: type,
                                         filter_operators: filter_table.forest_operators(name),
                                         is_primary_key: is_primary_key,
                                         is_groupable: false,
                                         is_read_only: true))
      end

      # A record read through the endpoint of an id that is not the primary key
      # it answered with. `GET /accounts/{id}` takes an external id and
      # `GET /issues/{id}` an issue number, so the record a lookup hands back
      # can carry an `id` other than the one the filter asked for: keeping it
      # would answer `id equals <alias>` with a row that does not match, where
      # the same filter combined with a scope — which goes through the search
      # endpoint instead — answers nothing at all.
      def matches_id?(record, id)
        record['id'].to_s == id.to_s
      end

      # An order no endpoint honours is reported rather than silently swallowed:
      # the rows come back in whatever order the API imposes.
      def warn_unsortable(sort)
        return if sort.nil? || sort.empty? || default_pk_sort?(sort)
        return if translate_sort(sort, sortable_fields).first

        ForestAdminDatasourcePylon.logger.warn(unsortable_warning)
      end

      # Overridden by collections whose endpoint can sort server-side.
      def sortable_fields
        {}
      end

      # Overridden to name the order the endpoint imposes instead, which is what
      # tells the operator what they got in place of the order they asked for.
      def unsortable_warning
        "[forest_admin_datasource_pylon] #{name} cannot honour the requested order."
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

      # Operators a custom field may advertise: the ones the endpoint accepts on
      # one, read off the same table the native columns come from. Declarations
      # outside this list are dropped at registration, so the schema never
      # advertises an operator the translator would refuse — and the empty table
      # of a collection filtering nothing server-side advertises none.
      def allowed_custom_field_operators
        filter_table::CUSTOM_FIELD_OPS.keys
      end

      private

      def define_schema    = raise(NotImplementedError, "#{self.class} did not implement define_schema")
      def define_relations = raise(NotImplementedError, "#{self.class} did not implement define_relations")

      def walker
        @walker ||= Pagination::CursorWalker.new
      end

      def id_values(node)
        return nil unless node.is_a?(Leaf) && node.field == 'id'
        return nil unless [Operators::EQUAL, Operators::IN].include?(node.operator)

        Array(node.value).map(&:to_s).reject(&:empty?)
      end

      def and_branch?(node)
        node.is_a?(Branch) && node.aggregator.to_s.casecmp('and').zero?
      end

      # An `id` the short-circuit could not take out of the tree has no
      # translation left: the endpoint filters no id server-side, and an id under
      # an OR cannot be narrowed to a lookup because the other side of the union
      # would bring in records the lookup never fetched. The UI does offer both
      # an `id equals` filter and the or/and toggle, so this is worth an error an
      # operator can act on rather than the translator's "add it to api_filters".
      #
      # A collection whose endpoint does filter id declares it in `api_filters`
      # and never short-circuits, so the translator handles its ids like any
      # other field and there is nothing to refuse.
      def ensure_no_stray_id!(node)
        return if node.nil? || api_filters.key?('id')
        return unless node.some_leaf { |leaf| leaf.field == 'id' }

        raise UnsupportedOperatorError,
              "A filter on 'id' has to be combined with 'and' conditions only: Pylon cannot filter on id, so the " \
              'agent reads the records by id and applies the rest in memory, which an id inside an `or` would ' \
              'silently widen. Rewrite the filter with `and`, or filter on another field.'
      end

      # Forest offers a filter on a related field as soon as a ManyToOne is
      # declared, and sends it as a `relation:field` leaf. Pylon has no join and
      # no include parameter, so there is nothing to translate it into: the
      # matching records would have to be read from the foreign collection and
      # their keys matched here, which is a read of its own, not a filter.
      #
      # Refused with the foreign key of the relation, which is the filter the
      # operator can set instead — and the one the reverse side is listed by.
      def ensure_no_relation_leaf!(node)
        return if node.nil?

        field = nil
        node.some_leaf { |leaf| field = leaf.field if leaf.field.to_s.include?(':') }
        raise_unfilterable_relation(field) if field
      end

      def raise_unfilterable_relation(field)
        relation = schema[:fields][field.to_s.split(':').first]
        instead = if relation.respond_to?(:foreign_key)
                    "Filter on '#{relation.foreign_key}' instead, or set the filter from the " \
                      "#{relation.foreign_collection} list."
                  else
                    'Filter on a column of this collection instead.'
                  end

        raise UnsupportedOperatorError,
              "Pylon cannot filter on the related field '#{field}': it has no join, so a condition on a " \
              "relation has no server-side translation. #{instead}"
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

      # `ConditionTreeLeaf#match` compares with a bare `<` / `>`, which raises a
      # NoMethodError on a column Pylon leaves null -- `resolution_time` on an
      # unresolved issue, for one. Pairing the comparison with a presence check
      # reproduces what a database does with NULL, excluding the record, and
      # rides on the in-memory equivalence PRESENT already has for every type.
      def guard_nil_comparisons(node)
        return nil if node.nil?

        node.replace_leafs do |leaf|
          next leaf unless NIL_UNSAFE_OPERATORS.include?(leaf.operator)

          ConditionTreeFactory.intersect([Leaf.new(leaf.field, Operators::PRESENT), leaf])
        end
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
