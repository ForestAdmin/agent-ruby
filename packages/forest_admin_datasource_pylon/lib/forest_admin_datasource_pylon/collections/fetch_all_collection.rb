module ForestAdminDatasourcePylon
  module Collections
    # Base for the collections whose Pylon endpoint hands back the whole
    # collection of the organization in a single response: `GET /users` and
    # `GET /teams` take no cursor, no filter and no sort at all.
    #
    # Filtering, sorting and paginating that response in memory is exact rather
    # than approximate: the records in hand ARE every record Pylon holds, so a
    # window cut out of them carries the same rows a server-side query would
    # have returned. This is what keeps the in-memory pass out of the trap this
    # datasource refuses elsewhere — a result that looks filtered without being
    # filtered — which only arises when a single page of a larger dataset is all
    # one has. The cost is bandwidth, not correctness.
    #
    # Each `list` re-reads the endpoint, so what the operator sees is what Pylon
    # holds now rather than what it held when the process booted. One request
    # per list against the 300 a minute these endpoints grant, spaced out by
    # `RateLimiter`, is a budget no list view comes near.
    class FetchAllCollection < BaseCollection
      # The filters a column may advertise, per column type. Restricted to the
      # operators `ConditionTreeLeaf#match` evaluates natively or
      # `ConditionTreeEquivalent` rewrites into that native set, because the
      # in-memory pass is the only pass there is here: an operator with no
      # equivalence makes `match` return nil, which `apply` reads as "no match"
      # and would silently empty the page instead of filtering it.
      OPERATOR_CANDIDATES = {
        'String' => [Operators::EQUAL, Operators::NOT_EQUAL, Operators::IN, Operators::NOT_IN,
                     Operators::PRESENT, Operators::BLANK, Operators::CONTAINS, Operators::I_CONTAINS,
                     Operators::NOT_CONTAINS, Operators::STARTS_WITH, Operators::ENDS_WITH],
        'Boolean' => [Operators::EQUAL, Operators::NOT_EQUAL, Operators::IN, Operators::NOT_IN,
                      Operators::PRESENT, Operators::BLANK]
      }.freeze

      # Candidates are re-checked against the toolkit rather than trusted, so an
      # equivalence the toolkit stops providing takes the filter out of the
      # schema instead of turning every page using it into an empty one.
      def self.operators_for(column_type)
        Array(OPERATOR_CANDIDATES[column_type]).select do |operator|
          Equivalent.equivalent_tree?(operator, IN_MEMORY_OPERATORS, column_type)
        end
      end

      def list(caller, filter, projection)
        records = sort_in_memory(filtered_records(caller, filter), filter&.sort)

        page_window(records, filter).map { |record| project(record, projection) }
      end

      # Exact, like the filter and the sort above it: the records in hand are
      # every record Pylon holds, so a count or a group computed over them is
      # the one a server-side aggregation would have answered — which is why
      # these columns stay groupable where every other Pylon column is not.
      #
      # The rows are keyed with strings because that is how the agent reads
      # them, while `Aggregation#apply` hands them back keyed with symbols.
      def aggregate(caller, filter, aggregation, limit = nil)
        aggregation.apply(filtered_records(caller, filter), timezone_for(caller), limit)
                   .map { |row| { 'group' => row[:group], 'value' => row[:value] } }
      end

      # One request answers any number of ids: the endpoint hands back the
      # complete dataset, so the ids only pick rows out of it. Read again on
      # every pass, like `list` — the freshness this collection trades bandwidth
      # for is not worth losing to a cache of related records.
      #
      # Only the wanted entities are serialized: a page of a pointing collection
      # asks for a handful of ids, against every record the organization has.
      def records_indexed_by_id(ids)
        wanted = Array(ids)

        fetch_all.each_with_object({}) do |entity, indexed|
          next unless entity.is_a?(Hash) && wanted.include?(entity['id'])

          indexed[entity['id']] = serialize(entity)
        end
      end

      protected

      # A column is read-only unless the collection declares it `writable`.
      # Scalar columns are sortable and groupable because the in-memory sort and
      # aggregation honour anything asked of them; a Json column is none of the
      # three, as it holds a list whose Pylon semantics have no in-memory
      # counterpart — the same reason the primary-key residual guard refuses one.
      def add_column(name, type, is_primary_key: false, writable: false)
        add_field(name, ColumnSchema.new(column_type: type,
                                         filter_operators: self.class.operators_for(type),
                                         is_primary_key: is_primary_key,
                                         is_sortable: type != 'Json',
                                         is_groupable: type != 'Json',
                                         is_read_only: !writable))
      end

      # Pylon defines custom fields on issues, accounts and contacts only, so
      # neither collection read this way has any. Refused rather than ignored:
      # `serialize` has no hook here to read a custom-field value with, and the
      # in-memory pass no table to clamp the declared operators against, so a
      # declaration would register a column reading nil on every row forever.
      def add_custom_fields(custom_fields)
        return [] if custom_fields.empty?

        raise ConfigurationError,
              "#{name} takes no custom field: Pylon defines them on issues, accounts and contacts only."
      end

      # The complete collection, straight from its unpaginated endpoint.
      def fetch_all = raise(NotImplementedError, "#{self.class} did not implement fetch_all")

      # One Pylon entity flattened into a record matching the schema.
      def serialize(_entity) = raise(NotImplementedError, "#{self.class} did not implement serialize")

      private

      # The complete dataset, serialized and narrowed to the rows the filter
      # keeps: what `list` pages and what `aggregate` counts are the same rows.
      #
      # Relation conditions are resolved first, like everywhere else: neither
      # collection read this way declares a ManyToOne today, so what this refuses
      # is a condition on the reverse side, which `match` would otherwise read as
      # a missing column and answer by dropping every row.
      def filtered_records(caller, filter)
        with_resolved_relations(caller, filter) do |query|
          filter_in_memory(fetch_all.map { |entity| serialize(entity) }, caller, query)
        end
      end

      # The tree is applied over the complete dataset, so the rows it keeps are
      # the rows Pylon would have kept. `guard_nil_comparisons` is still worth
      # its cost: nothing in the schema advertises a bare comparison, but a
      # scope, a segment or a customizer can send one, and it would otherwise
      # raise on the nulls Pylon returns for an unset column.
      def filter_in_memory(records, caller, filter)
        tree = guard_nil_comparisons(filter&.condition_tree)
        return records if tree.nil?

        tree.apply(records, self, timezone_for(caller))
      end

      # Every requested order is honoured, including the ascending primary-key
      # sort the agent injects when the request asks for none, so there is no
      # unsortable order to report.
      #
      # Neither Ruby's `sort` nor the toolkit's `Sort#apply` can be used as is:
      # `sort` is not stable, and `<=>` answers nil on a null, on two booleans
      # and on mixed types, which leaves the comparator undefined and the order
      # arbitrary. Ties therefore fall back to the position the API returned the
      # record in, and values are compared by `compare_values`.
      def sort_in_memory(records, sort)
        clauses = normalized_sort_clauses(sort)
        return records if clauses.empty?

        records.each_with_index.sort do |(left, left_index), (right, right_index)|
          compare_clauses(left, right, clauses).nonzero? || (left_index <=> right_index)
        end.map(&:first)
      end

      def compare_clauses(left, right, clauses)
        clauses.each do |field, ascending|
          comparison = compare_values(left[field], right[field])
          next if comparison.zero?

          return ascending ? comparison : -comparison
        end

        0
      end

      # Nulls sort last on an ascending order and first on a descending one, the
      # way a database orders them; values `<=>` cannot compare — two booleans,
      # for one — are compared through their string form rather than left
      # undefined, which puts `false` before `true`, again like a database.
      def compare_values(left, right)
        return 0 if left.nil? && right.nil?
        return 1 if left.nil?
        return -1 if right.nil?

        (left <=> right) || (left.to_s <=> right.to_s)
      end
    end
  end
end
