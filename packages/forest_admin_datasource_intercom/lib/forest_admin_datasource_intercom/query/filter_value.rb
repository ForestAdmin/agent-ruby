module ForestAdminDatasourceIntercom
  module Query
    # How the value of a Forest condition reaches Intercom's search DSL, and
    # every way it can fail to. Split from the translator, which knows the shape
    # of the tree but not what a field expects on the wire.
    #
    # Intercom types its filter values: a date is epoch seconds, a number is a
    # number, a flag is a boolean. A value of the wrong shape is refused with
    # `data_invalid`, the same code an unsupported operator returns, so the
    # conversion belongs here rather than in a rescue reading error codes.
    class FilterValue
      # What the frontend sends for a Dateonly column, and what a segment written
      # in Ruby carries: a day with no time of day, which is midnight in the
      # timezone of whoever wrote the filter rather than in the server's.
      DATE_ONLY = /\A\d{4}-\d{2}-\d{2}\z/

      INTEGER = /\A-?\d+\z/

      def initialize(collection:, timezone: nil)
        @collection = collection
        identifier = timezone.to_s.strip
        # Stored stripped rather than only checked stripped: kept as it came, a
        # `" Europe/Paris "` passes the blank guard and then fails the zone
        # lookup, and a day boundary lands an offset away from where the filter
        # meant it.
        @timezone = identifier.empty? ? 'UTC' : identifier
        @day_bounds = DayBounds.new(collection: collection, timezone: @timezone)
      end

      def call(leaf, field, spelling)
        return list(leaf, field) if OperatorTable.list_operator?(spelling)

        refuse_absence!(leaf, field) if blank?(leaf.value)

        value = scalar(leaf.value, leaf, field)
        field.type == 'date' ? @day_bounds.call(value, spelling) : value
      end

      private

      # Dropping the blanks would answer a different question: `not_in [nil,
      # 'open']` was asked to exclude the records carrying neither and would come
      # back including them. An empty list is as bad the other way round, being a
      # filter that matches everything.
      def list(leaf, field)
        values = Array(leaf.value)
        refuse_empty_list!(leaf) if values.empty?
        refuse_absence!(leaf, field) if values.any? { |value| blank?(value) }

        values.map { |value| scalar(value, leaf, field) }
      end

      def scalar(value, leaf, field)
        case field.type
        when 'date' then epoch(value, leaf)
        when 'number' then number(value, leaf)
        when 'boolean' then boolean(value, leaf)
        else value.to_s
        end
      end

      # Intercom stores and compares its dates as epoch seconds. What arrives
      # here is an ISO8601 string most of the time -- the frontend sends one, and
      # so does every interval operator the toolkit rewrites into a pair of
      # bounds -- but a scope or a segment written in Ruby carries a Time or a
      # Date, and neither has a timezone of its own.
      def epoch(value, leaf)
        case value
        when DateTime then value.to_time.to_i
        when Date then start_of_day(value)
        when Time, Numeric then value.to_i
        when String then parse(value, leaf)
        else refuse_value!(leaf, value, 'a date')
        end
      end

      def parse(value, leaf)
        return start_of_day(Date.parse(value)) if DATE_ONLY.match?(value)

        Time.parse(value).to_i
      rescue ArgumentError, TypeError
        refuse_value!(leaf, value, 'a date')
      end

      # A day with no time of day is the caller's day, not the server's: it is
      # the timezone the filter was written in that says when that day starts.
      def start_of_day(date)
        Time.use_zone(@timezone) { Time.zone.local(date.year, date.month, date.day).to_i }
      rescue ArgumentError
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] unknown timezone #{@timezone.inspect}, reading the day boundary of a " \
          'date filter in UTC instead.'
        )
        Time.utc(date.year, date.month, date.day).to_i
      end

      # The agent casts every Number column with `to_f`, so an integer field
      # would be filtered with `42.0` -- a form none of its values carry. A float
      # with nothing after the point travels as the integer it is.
      #
      # A cast that overflowed to Infinity, or a NaN, is refused rather than
      # passed on: the JSON encoder raises on both, a step later, as a 500 naming
      # nothing the operator can act on.
      def number(value, leaf)
        case value
        when Integer then value
        when Float then finite(value, leaf)
        when String then value.match?(INTEGER) ? value.to_i : finite(Float(value, exception: false), leaf)
        else refuse_value!(leaf, value, 'a number')
        end
      end

      def finite(value, leaf)
        refuse_value!(leaf, value, 'a number') unless value.is_a?(Float) && value.finite?

        value == value.to_i ? value.to_i : value
      end

      def boolean(value, leaf)
        case value
        when true, false then value
        when 'true' then true
        when 'false' then false
        else refuse_value!(leaf, value, 'a true or a false')
        end
      end

      def blank?(value) = value.nil? || value.to_s.empty?

      # `present`, `blank` and `missing` are derived by the agent from an
      # equality, above this datasource, and rewritten into a comparison with an
      # empty value. Intercom's search matches values and has no spelling for the
      # absence of one, so the rewritten condition is refused here rather than
      # sent as a comparison against the empty string -- which Intercom would
      # answer as if it were a value of its own.
      def refuse_absence!(leaf, field)
        raise UnsupportedOperatorError,
              "#{@collection} cannot filter #{leaf.field.inspect} for absence: Intercom's search matches values " \
              "and has no operator for the lack of one, so a #{leaf.operator} condition on " \
              "#{field.field.inspect} cannot be translated. Filter on a value instead."
      end

      def refuse_empty_list!(leaf)
        raise UnsupportedOperatorError,
              "#{@collection} was asked to filter #{leaf.field.inspect} with #{leaf.operator} and an empty list, " \
              'which names no record and no filter. Pass at least one value.'
      end

      def refuse_value!(leaf, value, expected)
        raise UnsupportedOperatorError,
              "#{@collection} cannot filter #{leaf.field.inspect} with #{value.inspect}: Intercom expects " \
              "#{expected} on this field."
      end
    end
  end
end
