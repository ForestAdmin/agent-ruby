require 'active_support/core_ext/time/zones'

module ForestAdminDatasourceZendesk
  module Query
    # See https://developer.zendesk.com/api-reference/ticketing/ticket-management/search/
    #
    # Unsupported operators raise UnsupportedOperatorError rather than
    # silently producing the wrong query. Only the AND aggregator is
    # supported (Zendesk Search has no general OR).
    class ConditionTreeTranslator
      Operators = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
      Branch    = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
      Leaf      = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

      def self.call(condition_tree, timezone: nil, custom_fields: {})
        return '' if condition_tree.nil?

        new(timezone: timezone, custom_fields: custom_fields).translate(condition_tree)
      end

      def initialize(timezone: nil, custom_fields: {})
        @timezone = timezone || 'UTC'
        @custom_fields = custom_fields || {}
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
                "Zendesk Search API does not support arbitrary OR aggregation; got #{branch.aggregator.inspect}"
        end

        branch.conditions.map { |c| translate(c) }.reject(&:empty?).join(' ')
      end

      def translate_leaf(leaf)
        field = mapped_field(leaf.field)
        value = leaf.value

        if leaf.field == 'requester_email' && leaf.operator == Operators::EQUAL
          return "requester:#{format_value(value)}"
        end

        case leaf.operator
        when Operators::EQUAL        then "#{field}:#{format_value(value)}"
        when Operators::NOT_EQUAL    then "-#{field}:#{format_value(value)}"
        when Operators::IN           then translate_in(field, value, negate: false)
        when Operators::NOT_IN       then translate_in(field, value, negate: true)
        when Operators::GREATER_THAN, Operators::AFTER  then "#{field}>#{format_value(value)}"
        when Operators::LESS_THAN,    Operators::BEFORE then "#{field}<#{format_value(value)}"
        when Operators::PRESENT      then "#{field}:*"
        when Operators::BLANK        then "-#{field}:*"
        else
          raise UnsupportedOperatorError,
                "Zendesk datasource does not yet translate operator '#{leaf.operator}' on field '#{field}'"
        end
      end

      # An empty `IN []` would translate to '', which the branch then drops —
      # silently turning "match nothing" into "match everything". Raise instead.
      def translate_in(field, value, negate:)
        values = Array(value)
        if values.empty?
          raise UnsupportedOperatorError,
                "#{negate ? "NOT_IN" : "IN"} on field '#{field}' was given an empty array; " \
                'pass at least one value or use the BLANK / PRESENT operators.'
        end

        prefix = negate ? '-' : ''
        values.map { |v| "#{prefix}#{field}:#{format_value(v)}" }.join(' ')
      end

      def mapped_field(field)
        @custom_fields[field] || field
      end

      def format_value(value)
        case value
        when nil            then raise_nil_value_error
        when Time, DateTime then value.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
        when Date           then format_date(value)
        when String         then format_string(value)
        else                     value.to_s
        end
      end

      # `field:` with a nil value would parse as a presence check on Zendesk's
      # side — silently the wrong query. PRESENT / BLANK is the supported path.
      def raise_nil_value_error
        raise UnsupportedOperatorError,
              'Filter value is nil; use the PRESENT or BLANK operator to filter for absence.'
      end

      def format_date(value)
        Time.use_zone(@timezone) do
          Time.zone.local(value.year, value.month, value.day).utc.strftime('%Y-%m-%dT%H:%M:%SZ')
        end
      rescue ArgumentError
        ForestAdminDatasourceZendesk.logger.warn(
          "[forest_admin_datasource_zendesk] unknown timezone '#{@timezone}', falling back to UTC"
        )
        value.strftime('%Y-%m-%dT00:00:00Z')
      end

      def format_string(value)
        return value unless value.match?(/[\s"():-]/)

        %("#{value.gsub('"', '\\"')}")
      end
    end
  end
end
