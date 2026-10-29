module ForestAdminDatasourceIntercom
  module Collections
    # Collections Intercom returns whole in one unpaginated response, so filtering, sorting and
    # counting in memory is exact. The response is cached for `reference_cache_ttl` (0 disables).
    class FetchAllCollection < BaseCollection # rubocop:disable Metrics/ClassLength
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
        client.with_read_scope do
          records = sort_in_memory(filtered_records(caller, filter), filter&.sort)
          window = page_window(records, filter)
          rows = window.map { |record| project(record, projection) }

          enrich(window, rows, projection)
          embed_relations(caller, window, rows, projection)
          rows
        end
      end

      # Relations are embedded first: a group through one (`team:name`) would otherwise read nil
      # and fold every row into one group.
      def aggregate(caller, filter, aggregation, limit = nil)
        client.with_read_scope do
          records = filtered_records(caller, filter)
          rows = records.map(&:dup)
          embed_relations(caller, records, rows, aggregation.projection)

          aggregation.apply(rows, timezone_for(caller), limit)
                     .map { |row| { 'group' => row[:group], 'value' => row[:value] } }
        end
      end

      protected

      # Read-only: an editable column would offer a Save reaching an unimplemented `update`.
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

      # Not `sort`/`Sort#apply`: `sort` is unstable and `<=>` answers nil on nulls, booleans and
      # mixed types. Ties fall back to Intercom's order.
      def sort_in_memory(records, sort)
        clauses = sort_clauses(sort)
        return records if clauses.empty?

        records.each_with_index.sort do |(left, left_index), (right, right_index)|
          compare_clauses(left, right, clauses).nonzero? || (left_index <=> right_index)
        end.map(&:first)
      end

      # Unsortable clauses are dropped with a warning. They do arrive: `Filter#nest` prefixes the
      # condition tree but not the sort, so a many-to-many membership gets the target's columns.
      def sort_clauses(sort)
        known, unknown = Array(sort).partition { |clause| sortable_column?(sort_field(clause)) }
        warn_unsortable(unknown) unless unknown.empty?

        known.map { |clause| [sort_field(clause), ascending?(clause) != false] }
      end

      def sortable_column?(field)
        schema = fields[field]
        schema.is_a?(ColumnSchema) && schema.is_sortable
      end

      def warn_unsortable(clauses)
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] #{name} was asked to sort on " \
          "#{clauses.map { |clause| sort_field(clause).inspect }.join(", ")}, which it does not carry as a " \
          'sortable column; the rows ' \
          'come back in the order Intercom returned them. A related list through a many-to-many is ordered by the ' \
          'columns of the collection it travels through, not by those of the collection it reaches.'
        )
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
