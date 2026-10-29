module ForestAdminDatasourceIntercom
  module Query
    # Intercom truncates a date search to the UTC day (measured; the docs promise the workspace timezone):
    # `> V` starts at the day after V's, `< V` stops before V's day. Each bound is moved one day outward (a `<`
    # already on a day boundary stays) so Intercom answers the day the filter named: the window is day-granular.
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
