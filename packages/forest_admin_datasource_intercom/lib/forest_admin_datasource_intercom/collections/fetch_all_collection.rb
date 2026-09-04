module ForestAdminDatasourceIntercom
  module Collections
    # Base for the reference collections Intercom hands back whole in a single
    # response: admins, teams, ticket types, ticket states. Their endpoints
    # declare no pagination parameter, no filter and no sort.
    #
    # Paradoxically this is the most capable tier of the datasource. Filtering,
    # sorting, paginating and counting that response in memory is *exact* rather
    # than approximate, because the records in hand are every record Intercom
    # holds: a window cut out of them carries the rows a server-side query would
    # have returned. It is the one place where an in-memory pass does not risk
    # the thing this datasource refuses everywhere else -- a result that looks
    # filtered without being filtered -- which only arises when what one holds
    # is a single page of something larger. The cost is bandwidth, not
    # correctness.
    #
    # Each read re-reads the endpoint, so an operator sees what Intercom holds
    # now rather than what it held when the process booted. One request per list
    # against a 10 000-a-minute budget is not a figure any list view approaches.
    class FetchAllCollection < BaseCollection
      # The filters a column may advertise, per column type. Restricted to what
      # the toolkit can evaluate in memory, since the in-memory pass is the only
      # pass there is here: an operator with no equivalence makes `match` answer
      # nil, which `apply` reads as "no match" and would empty the page instead
      # of filtering it.
      OPERATOR_CANDIDATES = {
        'String' => [Operators::EQUAL, Operators::NOT_EQUAL, Operators::IN, Operators::NOT_IN,
                     Operators::PRESENT, Operators::BLANK, Operators::CONTAINS, Operators::I_CONTAINS,
                     Operators::NOT_CONTAINS, Operators::STARTS_WITH, Operators::ENDS_WITH],
        'Boolean' => [Operators::EQUAL, Operators::NOT_EQUAL, Operators::IN, Operators::NOT_IN,
                      Operators::PRESENT, Operators::BLANK]
      }.freeze

      # The operators `ConditionTreeLeaf#match` evaluates natively; anything else
      # needs an equivalence for the column's type to be evaluable at all.
      IN_MEMORY_OPERATORS = [Operators::IN, Operators::EQUAL, Operators::LESS_THAN, Operators::GREATER_THAN,
                             Operators::MATCH, Operators::STARTS_WITH, Operators::ENDS_WITH,
                             Operators::LONGER_THAN, Operators::SHORTER_THAN, Operators::INCLUDES_ALL,
                             Operators::NOT_IN, Operators::NOT_EQUAL, Operators::NOT_CONTAINS].freeze

      # Candidates are re-checked against the toolkit rather than trusted, so an
      # equivalence it stops providing takes the filter out of the schema instead
      # of turning every page using it into an empty one.
      def self.operators_for(column_type)
        Array(OPERATOR_CANDIDATES[column_type]).select do |operator|
          Equivalent.equivalent_tree?(operator, IN_MEMORY_OPERATORS, column_type)
        end
      end

      # Countable, unlike the cursor-paginated collections: the count answered
      # here is taken over every record Intercom holds rather than over the pages
      # a walk happened to collect.
      def initialize(datasource, name)
        super
        enable_count
      end

      def list(caller, filter, projection)
        records = sort_in_memory(filtered_records(caller, filter), filter&.sort)
        window = page_window(records, filter)
        rows = window.map { |record| project(record, projection) }

        enrich(window, rows, projection)
        embed_relations(caller, window, rows, projection)
        rows
      end

      # Exact, like the filter and the sort above it, which is why these columns
      # stay groupable.
      #
      # Rows come back keyed with strings because that is how the agent reads
      # them, while `Aggregation#apply` hands them back keyed with symbols.
      def aggregate(caller, filter, aggregation, limit = nil)
        aggregation.apply(filtered_records(caller, filter), timezone_for(caller), limit)
                   .map { |row| { 'group' => row[:group], 'value' => row[:value] } }
      end

      protected

      # Scalar columns are sortable and groupable, the in-memory pass honouring
      # anything asked of them. A Json column is neither, nor filterable: it
      # holds a list, and what a filter on it would mean has no in-memory
      # counterpart.
      #
      # Every column is read-only: this lot writes nothing, and an editable
      # column would offer a Save that reaches an `update` the collection does
      # not implement.
      def add_column(name, type, is_primary_key: false)
        add_field(name, ColumnSchema.new(column_type: type,
                                         filter_operators: self.class.operators_for(type),
                                         is_primary_key: is_primary_key,
                                         is_read_only: true,
                                         is_sortable: type != 'Json',
                                         is_groupable: type != 'Json'))
      end

      # Hook for what a row needs beyond the endpoint this collection reads --
      # a name held on the other side of a membership, say. Called with the rows
      # of the page only, and with the projection, so a column nobody asked for
      # costs no request.
      def enrich(_records, _rows, _projection); end

      # Every record of the collection, straight from its endpoint.
      def fetch_all = raise(NotImplementedError, "#{self.class} did not implement fetch_all")

      # One Intercom entity flattened into a record matching the schema.
      def serialize(_entity) = raise(NotImplementedError, "#{self.class} did not implement serialize")

      private

      # The complete dataset, serialized and narrowed to the rows the filter
      # keeps: what `list` pages and what `aggregate` counts are the same rows.
      def filtered_records(caller, filter)
        records = fetch_all.map { |entity| serialize(entity) }
        tree = filter&.condition_tree
        return records if tree.nil?

        # A condition through a relation becomes a membership on the foreign key:
        # this tier filters in memory, where a list of ids costs no more than one
        # id and none of Intercom's group limits apply -- they bound its search
        # DSL, which nothing here goes through.
        tree = rewrite_relation_conditions(caller, tree) { |key, ids, _| Leaf.new(key, Operators::IN, ids) }
        return [] if tree == NOTHING

        refuse_unevaluable!(tree)
        tree.apply(records, self, timezone_for(caller))
      end

      # A condition this collection cannot evaluate is refused rather than
      # applied. `match` answers nil for an operator with no in-memory
      # equivalence and `apply` reads that as "no match", so an unevaluable
      # condition would hand back an empty page that looks like a filter
      # matching nothing -- indistinguishable, to the operator, from a real
      # answer. The schema advertises no such operator; a scope, a segment or a
      # customizer can still send one.
      def refuse_unevaluable!(tree)
        offender = nil
        tree.some_leaf do |leaf|
          offender = leaf unless evaluable?(leaf)
          !offender.nil?
        end
        return if offender.nil?

        raise UnsupportedOperatorError,
              "#{name} cannot filter '#{offender.field}' with '#{offender.operator}': it is read whole from " \
              'Intercom and filtered in memory, which supports only the operators its columns advertise. ' \
              'Change the condition, or the scope or segment carrying it.'
      end

      def evaluable?(leaf)
        schema = fields[leaf.field]
        schema.is_a?(ColumnSchema) && schema.filter_operators.include?(leaf.operator)
      end

      # Neither Ruby's `sort` nor the toolkit's `Sort#apply` can be used as is:
      # `sort` is not stable, and `<=>` answers nil on a null, on two booleans
      # and on mixed types, which leaves the comparator undefined and the order
      # arbitrary. Ties therefore fall back to the position Intercom returned the
      # record in.
      #
      # Every requested order is honoured, the ascending primary-key sort the
      # agent injects when a request names none included, so there is no
      # unsortable order to report here -- unlike the cursor collections, where
      # Intercom ignores a sort without saying so.
      def sort_in_memory(records, sort)
        clauses = sort_clauses(sort)
        return records if clauses.empty?

        records.each_with_index.sort do |(left, left_index), (right, right_index)|
          compare_clauses(left, right, clauses).nonzero? || (left_index <=> right_index)
        end.map(&:first)
      end

      # A sort clause naming a field this collection does not carry is dropped:
      # ordering by a column that is not there would compare nil to nil on every
      # row and leave the order to the tie-break.
      def sort_clauses(sort)
        Array(sort).filter_map do |clause|
          field = clause[:field] || clause['field']
          next unless fields.key?(field)

          # `key?` rather than `||`: a descending clause carries `false`, which an
          # `||` fallback would read as "absent" and turn back into ascending.
          ascending = clause.key?(:ascending) ? clause[:ascending] : clause['ascending']
          [field, ascending != false]
        end
      end

      def compare_clauses(left, right, clauses)
        clauses.each do |field, ascending|
          comparison = compare_values(left[field], right[field])
          next if comparison.zero?

          return ascending ? comparison : -comparison
        end

        0
      end

      # Nulls sort last ascending and first descending, the way a database orders
      # them; values `<=>` cannot compare -- two booleans, for one -- are
      # compared through their string form rather than left undefined, which puts
      # `false` before `true`, again like a database.
      def compare_values(left, right)
        return 0 if left.nil? && right.nil?
        return 1 if left.nil?
        return -1 if right.nil?

        (left <=> right) || (left.to_s <=> right.to_s)
      end
    end
  end
end
