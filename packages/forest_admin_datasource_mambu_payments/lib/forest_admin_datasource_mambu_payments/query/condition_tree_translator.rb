module ForestAdminDatasourceMambuPayments
  module Query
    # Translates a Forest condition tree into a hash of Numeral query params.
    #
    # The previous version of `fetch_records` short-circuited on `id` and
    # otherwise sent an unfiltered list — silently producing wrong counts and
    # missing rows whenever the UI applied a non-id predicate. This translator
    # raises `UnsupportedOperatorError` for anything it cannot map, so the
    # failure mode is "loud error" rather than "wrong data".
    #
    # Each collection declares its server-filterable fields via `api_filters`:
    #
    #   { 'connected_account_id' => { ops: [EQUAL, IN], param: 'connected_account_id' } }
    #
    # `param` defaults to the field name. EQUAL emits a scalar value, IN emits
    # an Array (the client joins arrays with commas — see `Client#normalize_params`).
    # Top-level OR aggregation is rejected: Numeral list endpoints have no
    # general OR support, so silently translating "A or B" to "A and B" would
    # be wrong in both directions.
    class ConditionTreeTranslator
      Operators = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
      Branch    = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
      Leaf      = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

      def self.call(condition_tree, api_filters: {})
        return {} if condition_tree.nil?

        new(api_filters).translate(condition_tree)
      end

      def initialize(api_filters)
        @api_filters = api_filters || {}
      end

      def translate(node)
        case node
        when Branch then translate_branch(node)
        when Leaf   then translate_leaf(node)
        else
          raise UnsupportedOperatorError, "Unknown condition node: #{node.class}"
        end
      end

      private

      def translate_branch(branch)
        unless branch.aggregator.to_s.casecmp('and').zero?
          raise UnsupportedOperatorError,
                "Mambu Payments list endpoints do not support OR aggregation (got #{branch.aggregator.inspect}). " \
                'Split the request into separate filters.'
        end

        branch.conditions.each_with_object({}) do |condition, acc|
          translate(condition).each do |key, value|
            if acc.key?(key)
              raise UnsupportedOperatorError,
                    "Conflicting predicates on '#{key}': cannot pass the same query param twice."
            end

            acc[key] = value
          end
        end
      end

      def translate_leaf(leaf)
        spec = @api_filters[leaf.field]
        unless spec
          raise UnsupportedOperatorError,
                "Mambu Payments datasource does not yet translate filters on '#{leaf.field}'. " \
                'Add it to the collection\'s `api_filters` after verifying the Numeral docs.'
        end

        param = (spec[:param] || leaf.field).to_s
        ops   = Array(spec[:ops])
        unless ops.include?(leaf.operator)
          raise UnsupportedOperatorError,
                "Operator '#{leaf.operator}' is not supported on field '#{leaf.field}'. " \
                "Supported: #{ops.join(", ")}."
        end

        translate_value(param, leaf.operator, leaf.value)
      end

      def translate_value(param, operator, value)
        case operator
        when Operators::EQUAL
          raise_nil_value(param) if value.nil?
          { param => value }
        when Operators::IN
          values = Array(value).reject { |v| v.nil? || v.to_s.empty? }
          raise_empty_in(param) if values.empty?
          { param => values }
        else
          raise UnsupportedOperatorError,
                "Operator '#{operator}' is declared in api_filters but has no translation rule."
        end
      end

      # `field=` with a nil value would semantically degrade to "filter present" on
      # most REST APIs — silently the wrong query. Use PRESENT / BLANK instead
      # (once those operators are wired up here).
      def raise_nil_value(param)
        raise UnsupportedOperatorError,
              "Filter value on '#{param}' is nil; the PRESENT / BLANK operators are not yet supported."
      end

      # An empty `IN []` would translate to no params, silently turning
      # "match nothing" into "match everything". Raise instead.
      def raise_empty_in(param)
        raise UnsupportedOperatorError,
              "IN on '#{param}' was given an empty array; pass at least one value."
      end
    end
  end
end
