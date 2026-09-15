module ForestAdminDatasourceIntercom
  module Query
    # Where a date bound lands once Intercom's day truncation is accounted for.
    #
    # Intercom truncates a date search to the day, at the **UTC** boundary --
    # measured, and it contradicts the documentation, which promises the
    # workspace's timezone. `> V` answers from the start of the day *after* V,
    # and `< V` answers before the start of V's own day.
    #
    # Sent as they come, the two bounds of an interval cancel each other out:
    # `today` reaches here as `> 00:00` and `< 23:59` of one day, which Intercom
    # reads as "from tomorrow" and "before today" -- an empty answer to the most
    # ordinary filter there is. So each bound is moved to the day boundary that
    # makes Intercom answer the day the filter named:
    #
    #   `>` V  ->  the day before V's day, so the answer starts at V's day;
    #   `<` V  ->  the day after V's day, so the answer runs through V's day,
    #              except when V already sits on a boundary, where V's day is
    #              exactly what was asked to be left out.
    #
    # The window is therefore day-granular: a bound naming a time of day matches
    # from the start of that day, or through the end of it. That is the
    # granularity the Intercom interface filters on, and the README says so.
    #
    # Split from FilterValue, which knows how to read a date out of whatever a
    # condition carries but has no business knowing that Intercom answers a
    # different question from the one it was asked.
    class DayBounds
      UTC_DAY = 86_400

      def initialize(collection:, timezone:)
        @collection = collection
        @timezone = timezone
      end

      def call(seconds, spelling)
        day = seconds - (seconds % UTC_DAY)
        report_utc_day(seconds, day)

        return day - UTC_DAY if spelling == '>'

        seconds == day ? seconds : day + UTC_DAY
      end

      private

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
