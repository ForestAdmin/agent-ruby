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

      def self.call(condition_tree, endpoint:, collection:, timezone: nil)
        return nil if condition_tree.nil?

        new(endpoint: endpoint, collection: collection, timezone: timezone).translate(condition_tree)
      end

      def initialize(endpoint:, collection:, timezone: nil)
        @endpoint = endpoint
        @collection = collection
        @value = FilterValue.new(collection: collection, timezone: timezone)
      end

      def translate(node)
        case node
        when Branch then translate_branch(node)
        when Leaf then translate_leaf(node)
        else raise UnsupportedOperatorError, "#{@collection} cannot read #{node.class} as a condition."
        end
      end

      private

      def translate_branch(branch)
        conditions = Array(branch.conditions)
        refuse_empty_branch!(branch) if conditions.empty?

        # Read before the unwrap below, so a branch is refused on the aggregator
        # it carries rather than on how many conditions it holds.
        operator = aggregator(branch)

        # A branch holding one condition needs no group of its own. The agent
        # builds a tree one branch at a time -- a scope, then a segment, then the
        # operator's own filter -- and the nesting Intercom allows is shallow
        # enough that a wrapper around nothing is a level worth not spending.
        return translate(conditions.first) if conditions.size == 1

        { 'operator' => operator, 'value' => conditions.map { |condition| translate(condition) } }
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
