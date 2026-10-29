module ForestAdminDatasourceIntercom
  module Query
    # The timezone a filter was written in, and what reading a value in it
    # costs when the caller names one nothing knows.
    #
    # Split from FilterValue for the reason DayBounds was: that class knows
    # what shape a field expects on the wire, and whether a value carries the
    # caller's wall clock or the server's is a different question.
    class CallerZone
      # Kept stripped rather than only checked stripped: as it came, a
      # `" Europe/Paris "` passes the blank guard and then fails the zone
      # lookup, and a day boundary lands an offset away from where the filter
      # meant it.
      attr_reader :name

      def initialize(identifier)
        stripped = identifier.to_s.strip
        @name = stripped.empty? ? 'UTC' : stripped
      end

      # A day with no time of day is the caller's day, not the server's: it is
      # the timezone the filter was written in that says when that day starts.
      def start_of_day(date)
        read('the day boundary') { Time.zone.local(date.year, date.month, date.day).to_i }
      end

      # An offset-less timestamp is the caller's wall clock: FilterFactory writes previous-period bounds as
      # `%Y-%m-%d %H:%M:%S`, and a midnight shifted by any offset truncates onto another UTC day.
      def timestamp(value)
        read('the timestamp') { Time.zone.parse(value).to_i }
      end

      private

      # Falling back to UTC silently would move a boundary by the offset, which
      # is the failure a timezone is read for in the first place.
      def read(what, &block)
        Time.use_zone(@name, &block)
      rescue ArgumentError
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] unknown timezone #{@name.inspect}, reading #{what} of a date " \
          'filter in UTC instead.'
        )
        Time.use_zone('UTC', &block)
      end
    end
  end
end
