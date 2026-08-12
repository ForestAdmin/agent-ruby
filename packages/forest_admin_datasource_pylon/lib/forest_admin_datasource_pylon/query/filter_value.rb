require 'active_support/core_ext/time/zones'

module ForestAdminDatasourcePylon
  module Query
    # How a Forest filter value reaches the wire, and every way it can fail to.
    # Split from the translator, which knows the shape of the condition tree but
    # not the format of what the leaves carry.
    class FilterValue
      def initialize(timezone: nil)
        @timezone = timezone.to_s.strip.empty? ? 'UTC' : timezone
      end

      def single(leaf)
        raise_nil_value(leaf.field) if leaf.value.nil?

        format(leaf.value)
      end

      # Dropping the blanks would silently answer a different question: `not_in
      # [nil, 'open']` was asked to exclude the blank records and would come
      # back including them. An empty list is just as bad the other way round,
      # translating to a filter matching everything.
      def list(leaf)
        values = Array(leaf.value)
        raise_blank_in_list(leaf) if values.any? { |value| value.nil? || value.to_s.empty? }
        raise_empty_list(leaf) if values.empty?

        values.map { |value| format(value) }
      end

      private

      # Numbers and booleans travel as they are: the filter is JSON, not a query
      # string, so only the date types need a wire format.
      def format(value)
        case value
        when Time, DateTime then value.to_time.utc.iso8601
        when Date           then format_date(value)
        else                     value
        end
      end

      # Only reached by a condition tree built in Ruby -- a segment or a scope
      # written as code. Everything coming through HTTP arrives as an ISO8601
      # string, already expressed in the timezone of the caller: the agent casts
      # a date filter with `value.to_s`, and the toolkit formats the bounds it
      # derives from Today / Previous* itself.
      def format_date(value)
        Time.use_zone(@timezone) { Time.zone.local(value.year, value.month, value.day).utc.iso8601 }
      rescue ArgumentError
        ForestAdminDatasourcePylon.logger.warn(
          "[forest_admin_datasource_pylon] unknown timezone '#{@timezone}', falling back to UTC"
        )
        value.strftime('%Y-%m-%dT00:00:00Z')
      end

      # A filter carrying a nil value reads as a presence check on most APIs,
      # which is silently the wrong query.
      def raise_nil_value(field)
        raise UnsupportedOperatorError,
              "Filter value on '#{field}' is nil; use the PRESENT or BLANK operator to filter for absence."
      end

      def raise_blank_in_list(leaf)
        raise UnsupportedOperatorError,
              "Operator '#{leaf.operator}' on field '#{leaf.field}' was given a list holding a blank value; " \
              'Pylon matches an absent value through is_set / is_unset only, so filter for absence with the ' \
              'PRESENT or BLANK operator rather than listing nil or an empty string.'
      end

      def raise_empty_list(leaf)
        raise UnsupportedOperatorError,
              "Operator '#{leaf.operator}' on field '#{leaf.field}' was given an empty list; " \
              'pass at least one value.'
      end
    end
  end
end
