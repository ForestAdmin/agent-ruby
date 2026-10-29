module ForestAdminDatasourceIntercom
  module Query
    # Intercom types its filter values, and a wrongly shaped one fails with `data_invalid`, the same code as an
    # unsupported operator, so values are converted here rather than by reading error codes.
    # Long by line count only: most of it is the refusals, one per shape.
    class FilterValue # rubocop:disable Metrics/ClassLength
      # What the frontend sends for a Dateonly column, and what a segment written
      # in Ruby carries: a day with no time of day, which is midnight in the
      # timezone of whoever wrote the filter rather than in the server's.
      DATE_ONLY = /\A\d{4}-\d{2}-\d{2}\z/

      # What `Date._parse` has to have found for a string to name a day at all.
      DATE_PARTS = %i[year mon mday].freeze

      INTEGER = /\A-?\d+\z/

      # Measured on every list, whatever group it stands in: Intercom counts
      # each value as an element of a composite query and answers a 400 naming
      # neither the field nor the condition past 15.
      MAX_LIST_SIZE = 15

      def initialize(collection:, timezone: nil)
        @collection = collection
        @zone = CallerZone.new(timezone)
        @day_bounds = DayBounds.new(collection: collection, timezone: @zone.name)
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
        refuse_long_list!(leaf, values.size) if values.size > MAX_LIST_SIZE
        refuse_absence!(leaf, field) if values.any? { |value| blank?(value) }

        values.map { |value| scalar(value, leaf, field) }
      end

      def scalar(value, leaf, field)
        case field.type
        when 'date' then epoch(value, leaf)
        when 'number' then number(value, leaf)
        when 'boolean' then boolean(value, leaf)
        else field.value_map ? mapped(value.to_s, leaf, field) : value.to_s
        end
      end

      # A value outside the map is refused rather than sent as typed: Intercom
      # would compare it against a vocabulary the column never shows.
      def mapped(value, leaf, field)
        field.value_map.fetch(value) { refuse_value!(leaf, value, "one of #{field.value_map.keys.join(", ")}") }
      end

      # Intercom stores and compares its dates as epoch seconds. What arrives
      # here is an ISO8601 string most of the time -- the frontend sends one, and
      # so does every interval operator the toolkit rewrites into a pair of
      # bounds -- but a scope or a segment written in Ruby carries a Time or a
      # Date, and neither has a timezone of its own.
      def epoch(value, leaf)
        case value
        when DateTime then value.to_time.to_i
        when Date then @zone.start_of_day(value)
        when Time then value.to_i
        when Numeric then seconds(value, leaf)
        when String then parse(value, leaf)
        else refuse_value!(leaf, value, 'a date')
        end
      end

      # An Infinity or a NaN -- a cast that overflowed above this datasource --
      # makes `Integer()` raise a FloatDomainError naming a float where the
      # operator asked for a date, and a Complex a RangeError, which is the
      # same class one level up. Refused like every other value the field
      # cannot take, for the reason `number` refuses them too.
      def seconds(value, leaf)
        Integer(value)
      rescue RangeError, TypeError
        refuse_value!(leaf, value, 'a date')
      end

      # Refuses a string lacking a year, month or day instead of letting a parser complete it: `Time.zone.parse`
      # answers today for `last tuesday`, and `Time.parse` fills in the server's date for `12:00`.
      def parse(value, leaf)
        return @zone.start_of_day(Date.parse(value)) if DATE_ONLY.match?(value)

        refuse_value!(leaf, value, 'a date') unless dated?(value)

        @zone.timestamp(value)
      rescue ArgumentError, TypeError
        refuse_value!(leaf, value, 'a date')
      end

      def dated?(value)
        parts = Date._parse(value)

        DATE_PARTS.all? { |part| parts.key?(part) }
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

      def refuse_long_list!(leaf, size)
        raise UnsupportedOperatorError,
              "#{@collection} cannot filter #{leaf.field.inspect} with #{leaf.operator} and #{size} values: " \
              "Intercom takes #{MAX_LIST_SIZE} at most in one list. Narrow the list, or split the filter."
      end

      def refuse_value!(leaf, value, expected)
        raise UnsupportedOperatorError,
              "#{@collection} cannot filter #{leaf.field.inspect} with #{value.inspect}: Intercom expects " \
              "#{expected} on this field."
      end
    end
  end
end
