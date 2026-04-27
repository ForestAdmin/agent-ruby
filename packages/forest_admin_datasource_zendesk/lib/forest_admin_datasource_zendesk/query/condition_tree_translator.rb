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
    # Custom-field translation: when `Datasource#register_custom_field_translations`
    # has set `custom_field_mapping`, filters on a custom column are rewritten
    # to the Zendesk-side search field (e.g. `custom_360001234` →
    # `custom_field_360001234`, or `vip_tier` → `vip_tier` for keyed
    # user/org fields).
    #
    # Timezone handling: callers may pass `timezone:` to `.call`; Date values
    # are interpreted as start-of-day in that TZ, then converted to UTC.
    # Time/DateTime values are converted to UTC directly (they already carry
    # offset info). String values are passed through verbatim.
    class ConditionTreeTranslator
      Operators = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
      Branch    = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
      Leaf      = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

      class << self
        attr_accessor :custom_field_mapping

        def call(condition_tree, timezone: nil)
          return '' if condition_tree.nil?

          new(timezone: timezone).translate(condition_tree)
        end
      end

      self.custom_field_mapping = {}

      def initialize(timezone: nil)
        @timezone = timezone || 'UTC'
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
        when Operators::IN           then Array(value).map { |v| "#{field}:#{format_value(v)}" }.join(' ')
        when Operators::NOT_IN       then Array(value).map { |v| "-#{field}:#{format_value(v)}" }.join(' ')
        when Operators::GREATER_THAN, Operators::AFTER  then "#{field}>#{format_value(value)}"
        when Operators::LESS_THAN,    Operators::BEFORE then "#{field}<#{format_value(value)}"
        when Operators::PRESENT      then "#{field}:*"
        when Operators::BLANK        then "-#{field}:*"
        else
          raise UnsupportedOperatorError,
                "Zendesk datasource does not yet translate operator '#{leaf.operator}' on field '#{field}'"
        end
      end

      def mapped_field(field)
        self.class.custom_field_mapping[field] || field
      end

      def format_value(value)
        case value
        when Time, DateTime
          value.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
        when Date
          # Interpret a bare Date as 00:00 in the caller's timezone, then to UTC.
          # If activesupport's TZ table doesn't know the zone, fall back to UTC.
          Time.use_zone(@timezone) do
            Time.zone.local(value.year, value.month, value.day).utc.strftime('%Y-%m-%dT%H:%M:%SZ')
          end
        when String
          value.match?(/\s/) ? %("#{value}") : value
        else
          value.to_s
        end
      rescue ArgumentError
        # Unknown timezone identifier — degrade to UTC interpretation.
        ForestAdminDatasourceZendesk.logger.warn(
          "[forest_admin_datasource_zendesk] unknown timezone '#{@timezone}', falling back to UTC"
        )
        value.is_a?(Date) ? value.strftime('%Y-%m-%dT00:00:00Z') : value.to_s
      end
    end
  end
end
