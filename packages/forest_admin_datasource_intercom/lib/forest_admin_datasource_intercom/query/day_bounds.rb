module ForestAdminDatasourceIntercom
  module Query
    # Intercom truncates a date search to the UTC day (measured; the docs promise the workspace timezone):
    # `> V` starts at the day after V's, `< V` stops before V's day. Each bound is moved one day outward (a `<`
    # already on a day boundary stays) so Intercom answers the day the filter named: the window is day-granular.
    # A bound inside a day would be answered for the whole of it, rows outside the window included, so it is
    # refused -- `future`, `after_x_hours_ago`, a time of day. Except a `<` at the present (`past`, the
    # `*_to_date` family): widened to midnight it only adds rows dated after now, and a column holding past
    # instants has none.
    class DayBounds
      UTC_DAY = 86_400

      # The one filterable date that can lie ahead of the present.
      FUTURE_DATED = %w[snoozed_until].freeze

      # The toolkit reads the clock before this does and writes the bound to the second.
      CLOCK_SLACK = 5

      def initialize(collection:, timezone:, now: -> { Time.now.to_i })
        @collection = collection
        @timezone = timezone
        @now = now
      end

      def call(seconds, spelling, leaf, field)
        refuse_inside_a_day!(seconds, leaf) unless midnight?(seconds) || open_ended?(seconds, spelling, field)

        day = seconds - (seconds % UTC_DAY)
        report_utc_day(seconds, day)

        return day - UTC_DAY if spelling == '>'

        seconds == day ? seconds : day + UTC_DAY
      end

      private

      # The caller's midnight, which is where the toolkit puts the bounds of `today` and the previous periods,
      # or the UTC one, which is the day Intercom compares by.
      def midnight?(seconds)
        return true if (seconds % UTC_DAY).zero?

        Time.use_zone(@timezone) { Time.zone.at(seconds) == Time.zone.at(seconds).beginning_of_day }
      rescue ArgumentError
        false
      end

      def open_ended?(seconds, spelling, field)
        spelling == '<' && !FUTURE_DATED.include?(field.field) && seconds >= @now.call - CLOCK_SLACK
      end

      def refuse_inside_a_day!(seconds, leaf)
        raise UnsupportedOperatorError,
              "#{@collection} cannot filter #{leaf.field.inspect} on #{Time.at(seconds).utc.iso8601}, a time " \
              'inside a day: Intercom compares a date by the UTC day, so it would answer the whole day and ' \
              'return rows outside the window. Filter by day instead -- before or after a date, today, ' \
              'yesterday, a previous period.'
      end

      # A window written in another timezone is answered on the UTC days it
      # overlaps, which is up to a day wider at each end. Reported once per
      # filter rather than per bound: what an operator needs to know is that the
      # day boundary is not theirs, not how many bounds crossed it.
      def report_utc_day(seconds, day)
        return if @reported || same_day_locally?(seconds, day)

        @reported = true
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] #{@collection} was filtered on a date written in #{@timezone}, and " \
          'Intercom truncates a date search to the UTC day whatever the workspace timezone says. The rows come ' \
          'back for the UTC days the window overlaps, which is up to a day wider at each end.'
        )
      end

      def same_day_locally?(seconds, day)
        Time.use_zone(@timezone) { Time.zone.at(seconds).to_date } == Time.at(day).utc.to_date
      rescue ArgumentError
        true
      end
    end
  end
end
