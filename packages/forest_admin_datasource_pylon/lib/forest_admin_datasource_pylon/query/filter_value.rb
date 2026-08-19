require 'date'
require 'active_support/core_ext/time/zones'

module ForestAdminDatasourcePylon
  module Query
    # How a Forest filter value reaches the wire, and every way it can fail to.
    # Split from the translator, which knows the shape of the condition tree but
    # not the format of what the leaves carry.
    class FilterValue
      # A date carrying no time of day, which is what the frontend sends for a
      # Dateonly column -- a shape only a custom field has, no native column
      # being typed that way.
      DATE_ONLY = /\A\d{4}-\d{2}-\d{2}\z/

      def initialize(timezone: nil)
        @timezone = timezone.to_s.strip.empty? ? 'UTC' : timezone
      end

      # `time` says the operator this value travels with is one of Pylon's time
      # comparisons, which is what decides whether a bare date is a date or a
      # piece of text: the same string on a text field is a value of its own.
      def single(leaf, time: false)
        raise_nil_value(leaf.field) if leaf.value.nil?

        format(leaf.value, time: time)
      end

      # Dropping the blanks would silently answer a different question: `not_in
      # [nil, 'open']` was asked to exclude the blank records and would come
      # back including them. An empty list is just as bad the other way round,
      # translating to a filter matching everything.
      #
      # No time comparison takes a list, so nothing here is read as a date.
      def list(leaf)
        values = Array(leaf.value)
        raise_empty_list(leaf) if values.empty?
        raise_blank_in_list(leaf) if values.any? { |value| value.nil? || value.to_s.empty? }

        values.map { |value| format(value) }
      end

      private

      # Booleans travel as they are: the filter is JSON, not a query string, so
      # only the dates and the numbers the agent widened need a wire format.
      def format(value, time: false)
        case value
        when Time, DateTime then value.to_time.utc.iso8601
        when Date           then format_date(value)
        when Float          then format_float(value)
        when String         then time ? format_time_string(value) : value
        else                     value
        end
      end

      # The agent casts every Number column with `to_f`
      # (`ConditionTreeParser.cast_to_type`), so an integer custom field would be
      # filtered with `42.0` -- a form none of its values carry. A float with
      # nothing after the point travels as the integer it is; a decimal keeps its
      # own.
      def format_float(value)
        value == value.to_i ? value.to_i : value
      end

      # `time_is_after` receives a timestamp everywhere else in this datasource,
      # a native date column being read and filtered as one: a Dateonly custom
      # field cannot be the one field sending the same operator another shape.
      # The bound is the one a Ruby `Date` already gets -- midnight in the
      # timezone of the caller.
      #
      # A string this operator cannot read as a date is left to Pylon, which
      # names what it refuses better than a guess here would.
      def format_time_string(value)
        return value unless DATE_ONLY.match?(value)

        format_date(Date.parse(value))
      rescue Date::Error
        value
      end

      # Only reached by a condition tree built in Ruby -- a segment or a scope
      # written as code -- and by the bare date above. Everything else coming
      # through HTTP arrives as an ISO8601 timestamp, already expressed in the
      # timezone of the caller: the agent casts a date filter with `value.to_s`,
      # and the toolkit formats the bounds it derives from Today / Previous*
      # itself.
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
