module ForestAdminDatasourcePylon
  module Query
    # See https://docs.usepylon.com/pylon-docs/developer/api/api-reference/issues
    #
    # Translates a Forest condition tree into the structured JSON filter of
    # `POST /issues/search`:
    #
    #   leaf   -> { 'field' => …, 'operator' => …, 'value' | 'values' => … }
    #   branch -> { 'operator' => 'and' | 'or', 'subfilters' => [...] }
    #
    # Pylon nests sub-filters, so — unlike the Zendesk query string — OR is
    # translated natively instead of being rejected.
    #
    # Anything the API cannot express raises UnsupportedOperatorError: a filter
    # that is dropped returns unfiltered rows which look filtered. The wire
    # format of the values, and the refusals that go with it, live in FilterValue.
    class ConditionTreeTranslator
      Branch = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
      Leaf   = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

      # Pylon rejects sub-filters nested deeper than three levels.
      MAX_DEPTH = 3

      LIST_OPERATORS      = %w[in not_in].freeze
      VALUELESS_OPERATORS = %w[is_set is_unset].freeze

      # The comparisons Pylon reads as a moment in time: what tells FilterValue
      # that a bare date is a date, and not a piece of text a field happens to
      # hold. Read off the emitted operator rather than off the column type,
      # which the translator does not see -- and it is the operator that decides
      # the format anyway.
      TIME_OPERATORS      = %w[time_is_after time_is_before].freeze

      def self.call(condition_tree, api_filters: {}, timezone: nil)
        return nil if condition_tree.nil?

        new(api_filters: api_filters, timezone: timezone).translate(condition_tree)
      end

      def initialize(api_filters: {}, timezone: nil)
        @api_filters = api_filters || {}
        @value = FilterValue.new(timezone: timezone)
      end

      def translate(node, depth = 1)
        case node
        when Branch then translate_branch(node, depth)
        when Leaf   then translate_leaf(node)
        else
          raise UnsupportedOperatorError, "Unknown condition node: #{node.class}"
        end
      end

      private

      def translate_branch(branch, depth)
        conditions = Array(branch.conditions)
        if conditions.empty?
          raise UnsupportedOperatorError, "Condition tree aggregator '#{branch.aggregator}' carries no condition."
        end

        # Validated before the unwrap below, so a branch is refused on the
        # aggregator it carries rather than on how many conditions it holds.
        operator = aggregator(branch)

        # A lone condition needs no wrapper, and spending no nesting level on it
        # keeps trees the agent builds one branch at a time under Pylon's cap.
        return translate(conditions.first, depth) if conditions.size == 1

        raise_too_deep(depth) if depth > MAX_DEPTH

        { 'operator' => operator,
          'subfilters' => conditions.map { |condition| translate(condition, depth + 1) } }
      end

      def aggregator(branch)
        value = branch.aggregator.to_s.downcase
        return value if %w[and or].include?(value)

        raise UnsupportedOperatorError,
              "Unknown condition tree aggregator #{branch.aggregator.inspect}; expected 'And' or 'Or'."
      end

      def translate_leaf(leaf)
        spec = @api_filters[leaf.field]
        raise_unfilterable_field(leaf.field) unless spec

        operator = spec[:ops][leaf.operator]
        raise_unsupported_operator(leaf, spec) unless operator
        ensure_filterable_absence!(leaf, spec)

        with_value({ 'field' => (spec[:param] || leaf.field).to_s, 'operator' => operator }, operator, leaf)
      end

      def with_value(filter, operator, leaf)
        return filter if VALUELESS_OPERATORS.include?(operator)
        return filter.merge('values' => @value.list(leaf)) if LIST_OPERATORS.include?(operator)

        filter.merge('value' => @value.single(leaf, time: TIME_OPERATORS.include?(operator)))
      end

      # `present`, `blank` and `missing` are advertised on every field carrying
      # an equality or a membership filter: the agent derives them from those
      # above the datasource and rewrites them into a comparison with an empty
      # value. Only a field the API reference documents `is_set` / `is_unset` on
      # can answer one, and it answers it through those operators, never through
      # the rewritten comparison -- which Pylon would match against the empty
      # value as if it were a value of its own.
      #
      # Refused here rather than in FilterValue, which sees the empty value but
      # not whether the field has a presence filter to answer it with.
      def ensure_filterable_absence!(leaf, spec)
        return unless absence_condition?(leaf)
        return if spec[:ops].values.any? { |candidate| VALUELESS_OPERATORS.include?(candidate) }

        raise UnsupportedOperatorError,
              "Pylon cannot filter '#{leaf.field}' for absence: the field carries no is_set / is_unset filter " \
              'in the Pylon API reference, so a present, blank or missing condition on it cannot be translated. ' \
              'Filter for absence on a field that does, or filter on a value instead.'
      end

      # The shape the absence operators are rewritten into: a nil value, or a
      # list holding nothing but blanks. An empty list is not one of them -- it
      # comes from a filter carrying no value at all, which FilterValue reports.
      def absence_condition?(leaf)
        return true if leaf.value.nil?
        return false unless leaf.value.is_a?(Array) && leaf.value.any?

        leaf.value.all? { |value| value.nil? || value.to_s.empty? }
      end

      def raise_too_deep(depth)
        raise UnsupportedOperatorError,
              "Pylon rejects a filter nested deeper than #{MAX_DEPTH} levels (reached #{depth}); " \
              'flatten the segment or the filter.'
      end

      def raise_unfilterable_field(field)
        raise UnsupportedOperatorError,
              "Pylon cannot filter on '#{field}'; add it to the collection's api_filters " \
              'after checking it against the Pylon API reference.'
      end

      def raise_unsupported_operator(leaf, spec)
        raise UnsupportedOperatorError,
              "Operator '#{leaf.operator}' is not supported on field '#{leaf.field}'. " \
              "Supported: #{spec[:ops].keys.join(", ")}."
      end
    end
  end
end
