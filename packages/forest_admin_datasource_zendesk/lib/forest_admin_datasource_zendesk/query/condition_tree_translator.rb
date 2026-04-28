require 'active_support/core_ext/time/zones'

module ForestAdminDatasourceZendesk
  module Query
    # Translates a Forest ConditionTree into a Zendesk Search API query string.
    # See https://developer.zendesk.com/api-reference/ticketing/ticket-management/search/
    #
    # v1 supports: EQUAL, NOT_EQUAL, IN, NOT_IN, GREATER_THAN, LESS_THAN,
    # BEFORE, AFTER, PRESENT, BLANK. AND aggregator only.
    # Unsupported operators raise UnsupportedOperatorError so failures are
    # loud, not silent wrong results.
    #
    # Custom-field translation: callers pass `custom_fields:` (a hash from
    # Forest column names to Zendesk Search field names, owned by the
    # Datasource instance) so multi-tenant agents with several Zendesk
    # datasources don't trample each other's mappings.
    #
    # Timezone handling: callers pass `timezone:`; Date values are
    # interpreted as start-of-day in that TZ, then converted to UTC.
    # Time/DateTime values are converted to UTC directly (they already carry
    # offset info). String values are passed through verbatim, with internal
    # double quotes escaped when wrapping in quotes is needed.
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

        return "requester:#{format_value(value)}" if leaf.field == 'requester_email' && leaf.operator == Operators::EQUAL

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

      # `IN []` and `NOT_IN []` are nonsense filters that previously produced
      # an empty string, which the branch translator dropped — silently
      # turning "match nothing" into "match everything". Raise instead.
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

      # Forest's UI never naturally produces an EQUAL/NOT_EQUAL/IN with a nil
      # value (it uses PRESENT / BLANK for that). Falling through to
      # nil.to_s would emit a malformed `field:` clause that Zendesk's
      # search treats as a presence check — i.e. silently the wrong query.
      def raise_nil_value_error
        raise UnsupportedOperatorError,
              'Filter value is nil; use the PRESENT or BLANK operator to filter for absence.'
      end

      # A bare Date is interpreted as 00:00 in the caller's timezone, then
      # converted to UTC. If activesupport's TZ table doesn't recognise the
      # zone, fall back to UTC and log a warning.
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

      # Strings with whitespace OR internal double quotes need quoting so
      # Zendesk parses them as a single phrase. We backslash-escape internal
      # quotes per Zendesk's documented quoting rules; without this, a value
      # like `test "with" quotes` would emit a malformed query.
      def format_string(value)
        return value unless value.match?(/[\s"]/)

        %("#{value.gsub('"', '\\"')}")
      end
    end
  end
end
