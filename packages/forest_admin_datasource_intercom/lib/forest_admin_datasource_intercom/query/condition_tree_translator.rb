module ForestAdminDatasourceIntercom
  module Query
    # Turns a Forest condition tree into the query `POST /conversations/search`
    # and `POST /tickets/search` take:
    #
    #   leaf   -> { 'field' => ..., 'operator' => ..., 'value' => ... }
    #   branch -> { 'operator' => 'AND' | 'OR', 'value' => [...] }
    #
    # What it will not translate, it refuses. A condition dropped on the way to
    # Intercom comes back as a page of unfiltered records that looks filtered,
    # and every refusal below therefore names the field, the operator, or the
    # thing to change -- an operator reads that message and nothing else.
    #
    # Which field the endpoint filters, and with which operator, is not decided
    # here: it is `search_fields.yml`, measured against a real workspace. This
    # walks the tree and formats what the table allows.
    class ConditionTreeTranslator
      Branch = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
      Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

      AGGREGATORS = { 'and' => 'AND', 'or' => 'OR' }.freeze

      # Intercom nests a search two levels deep and takes fifteen conditions per
      # group. Both are checked here rather than left to the API: over either,
      # Intercom answers a 400 whose body names neither the limit nor the part of
      # the filter that reached it, and an operator reading it has no way of
      # knowing that their segment plus their scope plus their own filter is what
      # went over.
      MAX_DEPTH = 2
      MAX_GROUP_SIZE = 15

      def self.call(condition_tree, endpoint:, collection:, timezone: nil)
        return nil if condition_tree.nil?

        new(endpoint: endpoint, collection: collection, timezone: timezone).translate(condition_tree)
      end

      def initialize(endpoint:, collection:, timezone: nil)
        @endpoint = endpoint
        @collection = collection
        @value = FilterValue.new(collection: collection, timezone: timezone)
      end

      def translate(node, depth = 1)
        case node
        when Branch then translate_branch(node, depth)
        when Leaf then translate_leaf(node)
        else raise UnsupportedOperatorError, "#{@collection} cannot read #{node.class} as a condition."
        end
      end

      private

      def translate_branch(branch, depth)
        conditions = Array(branch.conditions)
        refuse_empty_branch!(branch) if conditions.empty?

        # Read before the unwrap below, so a branch is refused on the aggregator
        # it carries rather than on how many conditions it holds.
        operator = aggregator(branch)

        # A branch holding one condition needs no group of its own. The agent
        # builds a tree one branch at a time -- a scope, then a segment, then the
        # operator's own filter -- and the nesting Intercom allows is shallow
        # enough that a wrapper around nothing is a level worth not spending.
        return translate(conditions.first, depth) if conditions.size == 1

        refuse_too_deep!(depth) if depth > MAX_DEPTH
        refuse_too_wide!(branch, conditions.size) if conditions.size > MAX_GROUP_SIZE

        { 'operator' => operator, 'value' => conditions.map { |condition| translate(condition, depth + 1) } }
      end

      # What reaches this depth is a group inside a group inside a group. The
      # message names the shape rather than a number, since the tree an operator
      # can act on is the segment and the scope they wrote, not the one the agent
      # assembled out of them.
      def refuse_too_deep!(depth)
        raise UnsupportedOperatorError,
              "#{@collection} cannot answer this filter: Intercom nests a search #{MAX_DEPTH} levels deep and this " \
              "one reaches #{depth}. A group inside a group inside a group is one level too many -- flatten the " \
              'segment, the scope or the filter carrying the innermost one.'
      end

      # Fifteen is reached without trying: a scope, a segment and a filter add up,
      # and a condition naming several values is expanded into one condition per
      # value on the way here, Intercom taking no membership operator on these
      # fields.
      def refuse_too_wide!(branch, size)
        raise UnsupportedOperatorError,
              "#{@collection} cannot answer this filter: Intercom takes #{MAX_GROUP_SIZE} conditions per group and " \
              "this #{branch.aggregator} carries #{size}. A filter naming several values counts one condition per " \
              'value here, so narrowing the list, the segment or the scope is what brings it back under the limit.'
      end

      def aggregator(branch)
        AGGREGATORS[branch.aggregator.to_s.downcase] ||
          raise(UnsupportedOperatorError,
                "#{@collection} cannot read #{branch.aggregator.inspect} as a condition tree aggregator; " \
                "expected 'And' or 'Or'.")
      end

      def translate_leaf(leaf)
        field = @endpoint.field(leaf.field.to_s) || refuse_unfilterable!(leaf.field.to_s)
        spelling = OperatorTable.intercom_operator(field, leaf.operator) || refuse_operator!(leaf, field)

        { 'field' => field.field, 'operator' => spelling, 'value' => @value.call(leaf, field, spelling) }
      end

      # A column the endpoint does not filter, and the reason it does not, taken
      # from the table when it carries one: those reasons are the difference
      # between "no" and a message an operator can do something with.
      def refuse_unfilterable!(column)
        raise UnsupportedOperatorError, "#{@collection} cannot filter #{column.inspect}: #{unfilterable_reason(column)}"
      end

      def unfilterable_reason(column)
        return relation_reason(column) if column.include?(':')

        refusal = @endpoint.refusal(column)
        return refusal.reason if refusal

        "#{@endpoint.path} takes no filter on it. Filter on one of: #{@endpoint.filterable_columns.join(", ")}."
      end

      # A relation reaches the translator as `relation:field`. None of the
      # collections this endpoint serves declares one yet, so the condition can
      # only come from a scope or a segment written against a schema this
      # datasource does not have.
      def relation_reason(column)
        "#{@collection} declares no relation, so #{column.inspect} names a field it cannot reach. Filter on one " \
          "of its own columns: #{@endpoint.filterable_columns.join(", ")}."
      end

      def refuse_operator!(leaf, field)
        supported = OperatorTable.forest_operators(field)

        raise UnsupportedOperatorError,
              "#{@collection} cannot filter #{leaf.field.inspect} with #{leaf.operator.inspect}: " \
              "#{@endpoint.path} answers #{supported.join(", ")} on #{field.field.inspect} and nothing else."
      end

      def refuse_empty_branch!(branch)
        raise UnsupportedOperatorError,
              "#{@collection} was given a #{branch.aggregator} branch carrying no condition, which names no record " \
              'and no filter.'
      end
    end
  end
end
