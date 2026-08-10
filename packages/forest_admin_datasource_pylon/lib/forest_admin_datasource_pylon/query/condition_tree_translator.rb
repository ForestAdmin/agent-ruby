require 'active_support/core_ext/time/zones'

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
    # that is dropped returns unfiltered rows which look filtered.
    class ConditionTreeTranslator
      Operators = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
      Branch    = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
      Leaf      = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

      # Pylon rejects sub-filters nested deeper than three levels.
      MAX_DEPTH = 3

      LIST_OPERATORS      = %w[in not_in].freeze
      VALUELESS_OPERATORS = %w[is_set is_unset].freeze

      def self.call(condition_tree, api_filters: {}, timezone: nil)
        return nil if condition_tree.nil?

        new(api_filters: api_filters, timezone: timezone).translate(condition_tree)
      end

      def initialize(api_filters: {}, timezone: nil)
        @api_filters = api_filters || {}
        @timezone = timezone.to_s.strip.empty? ? 'UTC' : timezone
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

        # A lone condition needs no wrapper, and spending no nesting level on it
        # keeps trees the agent builds one branch at a time under Pylon's cap.
        return translate(conditions.first, depth) if conditions.size == 1

        raise_too_deep(depth) if depth > MAX_DEPTH

        { 'operator' => aggregator(branch),
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

        with_value({ 'field' => (spec[:param] || leaf.field).to_s, 'operator' => operator }, operator, leaf)
      end

      def with_value(filter, operator, leaf)
        return filter if VALUELESS_OPERATORS.include?(operator)
        return filter.merge('values' => list_value(leaf)) if LIST_OPERATORS.include?(operator)

        filter.merge('value' => single_value(leaf))
      end

      def single_value(leaf)
        raise_nil_value(leaf.field) if leaf.value.nil?

        format_value(leaf.value)
      end

      # An empty list would translate to a filter matching everything, turning
      # "match nothing" into its exact opposite.
      def list_value(leaf)
        values = Array(leaf.value).reject { |value| value.nil? || value.to_s.empty? }
        if values.empty?
          raise UnsupportedOperatorError,
                "Operator '#{leaf.operator}' on field '#{leaf.field}' was given an empty list; " \
                'pass at least one value, or use the PRESENT / BLANK operators.'
        end

        values.map { |value| format_value(value) }
      end

      # Numbers and booleans travel as they are: the filter is JSON, not a query
      # string, so only the date types need a wire format.
      def format_value(value)
        case value
        when Time, DateTime then value.to_time.utc.iso8601
        when Date           then format_date(value)
        else                     value
        end
      end

      def format_date(value)
        Time.use_zone(@timezone) { Time.zone.local(value.year, value.month, value.day).utc.iso8601 }
      rescue ArgumentError
        ForestAdminDatasourcePylon.logger.warn(
          "[forest_admin_datasource_pylon] unknown timezone '#{@timezone}', falling back to UTC"
        )
        value.strftime('%Y-%m-%dT00:00:00Z')
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

      # A filter carrying a nil value reads as a presence check on most APIs,
      # which is silently the wrong query.
      def raise_nil_value(field)
        raise UnsupportedOperatorError,
              "Filter value on '#{field}' is nil; use the PRESENT or BLANK operator to filter for absence."
      end
    end
  end
end
