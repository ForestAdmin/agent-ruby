require 'active_support/all'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Chart
      class ResultBuilder
        include ForestAdminDatasourceToolkit::Components::Charts
        include ForestAdminDatasourceToolkit::Utils

        TIME_FORMAT = {
          Day: '%d/%m/%Y',
          Week: 'W%V-%G',
          Month: '%b %y',
          Year: '%Y'
        }.freeze

        def value(value, previous_value = nil)
          ValueChart.new(value, previous_value).serialize
        end

        def distribution(data)
          data = HashHelper.convert_keys(data, :to_s).map do |key, value|
            { key: key, value: value }
          end

          PieChart.new(data).serialize
        end

        def percentage(value)
          PercentageChart.new(value).serialize
        end

        def objective(value, objective)
          ObjectiveChart.new(value, objective).serialize
        end

        def leaderboard(value)
          data = distribution(value).sort { |a, b| b[:value] - a[:value] }

          LeaderboardChart.new(data).serialize
        end

        # Add a TimeBasedChart based on a time range and a set of values.
        # @param time_range - The time range for the chart, specified as "Year", "Month", "Week" or "Day".
        # @param values - This is an array of objects with 'date' and 'value' properties
        # @returns {TimeBasedChart} Returns a TimeBasedChart representing the data within the specified
        # time range.
        #
        # @example
        # time_based(
        #  'Day',
        #   [
        #    { date: '2023-01-01', value: 42 },
        #    { date: '2023-01-02', value: 55 },
        #    { date: '2023-01-03', value: null },
        #   ]
        # );
        def time_based(time_range, values)
          return [] if values.nil?

          values = HashHelper.convert_keys(values, :to_sym)
          values = values.map { |date, value| { date: date, value: value } } unless values.is_a? Array
          data = build_time_based_chart_result(time_range, values)

          LineChart.new(data).serialize
        end

        # Add a MultipleTimeBasedChart based on a time range,
        # an array of dates, and multiple lines of data.
        #
        # @param time_range - The time range for the chart, specified as "Year", "Month", "Week" or "Day".
        # @param dates - An array of dates that define the x-axis values for the chart.
        # @param lines - An array of lines, each containing a label and an array of numeric data values (or null)
        # corresponding to the dates.
        # @returns {MultipleTimeBasedChart} Returns a MultipleTimeBasedChart representing multiple
        # lines of data within the specified time range.
        #
        # @example
        # multiple_time_based(
        #  'Day',
        #  [
        #    Date.new('1985-10-26'),
        #    Date.new('2011-10-05T14:48:00.000Z'),
        #    Date.new()
        #  ],
        #  [
        #    { label: 'line1', values: [1, 2, 3] },
        #    { label: 'line2', values: [3, 4, null] }
        #  ],
        # );
        def multiple_time_based(time_range, dates, lines)
          return { labels: nil, values: nil } if dates.nil? || lines.nil?

          formatted_times = nil
          formatted_lines = lines.map do |line|
            values = dates.each_with_index.with_object([]) do |(date, index), memo|
              memo.push({ date: date, value: line[:values][index] })
            end

            build_time_based = build_time_based_chart_result(time_range, values)
            formatted_times = build_time_based.map { |time_based| time_based[:label] } if formatted_times.nil?

            { key: line[:label], values: build_time_based.map { |time_based| time_based[:values][:value] } }
          end

          {
            labels: formatted_times,
            values: formatted_times&.length&.positive? ? formatted_lines : nil
          }
        end

        def smart(data)
          data
        end

        private

        def build_time_based_chart_result(time_range, points)
          return [] if points.empty?

          format = TIME_FORMAT[time_range.to_sym]
          formatted = {}
          points.each do |point|
            point[:date] = DateTime.parse(point[:date]) if point[:date].is_a? String
            label = point[:date].strftime(format)
            formatted[label] = (formatted[label] || 0) + point[:value] if point[:value].is_a? Numeric
          end

          data_points = []
          dates = points.map { |point| point[:date] }
                        .sort { |date_a, date_b| date_a - date_b }

          # first date
          current = dates.first.send(:"beginning_of_#{time_range.to_s.downcase}")
          last = dates.last

          while current <= last
            label = current.strftime(format)
            data_points << { label: label, values: { value: formatted[label] || 0 } }
            current += 1.send(time_range.to_s.downcase.to_sym)
          end

          data_points
        end
      end
    end
  end
end
