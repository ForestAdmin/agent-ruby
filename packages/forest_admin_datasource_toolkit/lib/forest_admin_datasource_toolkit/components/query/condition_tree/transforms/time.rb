require 'active_support/all'
require 'active_support/core_ext/numeric/time'

module ForestAdminDatasourceToolkit
  module Components
    module Query
      module ConditionTree
        module Transforms
          class Time
            def self.format(value)
              value.in_time_zone('UTC').iso8601
            end

            def self.compare(operator)
              {
                dependsOn: [operator],
                forTypes: ['Date', 'Dateonly'],
                replacer: lambda { |leaf, tz|
                  leaf.override(operator: operator, value: format(yield(Time.now.in_time_zone(tz), leaf.value)))
                }
              }
            end

            def self.interval(start_fn, end_fn)
              {
                dependsOn: [Operators::LESS_THAN, Operators::GREATER_THAN],
                forTypes: ['Date', 'Dateonly'],
                replacer: lambda { |leaf, tz|
                  ConditionTreeFactory.intersect(
                    [
                      leaf.override(operator: Operators::GREATER_THAN,
                                    value: format(start_fn.call(Time.now.in_time_zone(tz), leaf.value))),
                      leaf.override(operator: Operators::LESS_THAN,
                                    value: format(end_fn.call(Time.now.in_time_zone(tz), leaf.value)))
                    ]
                  )
                }
              }
            end

            def self.previous_interval(duration)
              interval(
                ->(now) { now.send("sub#{duration}").send("start_of#{duration}") },
                ->(now) { now.send("start_of#{duration}") }
              )
            end

            def self.previous_interval_to_date(duration)
              interval(
                ->(now) { now.send("start_of#{duration}") },
                ->(now) { now }
              )
            end

            def self.time_transforms
              {
                Operators::BEFORE => [compare(Operators::LESS_THAN) { |_now, value| Time.parse(value) }],
                Operators::AFTER => [compare(Operators::GREATER_THAN) { |_now, value| Time.parse(value) }],
                Operators::PAST => [compare(Operators::LESS_THAN) { |now| now }],
                Operators::FUTURE => [compare(Operators::GREATER_THAN) { |now| now }],
                Operators::BEFORE_X_HOURS_AGO => [compare(Operators::LESS_THAN) { |now, value| now - value.hours }],
                Operators::AFTER_X_HOURS_AGO => [compare(Operators::GREATER_THAN) { |now, value| now - value.hours }],
                Operators::PREVIOUS_WEEK_TO_DATE => [previous_interval_to_date('week')],
                Operators::PREVIOUS_MONTH_TO_DATE => [previous_interval_to_date('month')],
                Operators::PREVIOUS_QUARTER_TO_DATE => [previous_interval_to_date('quarter')],
                Operators::PREVIOUS_YEAR_TO_DATE => [previous_interval_to_date('year')],
                Operators::YESTERDAY => [previous_interval('day')],
                Operators::PREVIOUS_WEEK => [previous_interval('week')],
                Operators::PREVIOUS_MONTH => [previous_interval('month')],
                Operators::PREVIOUS_QUARTER => [previous_interval('quarter')],
                Operators::PREVIOUS_YEAR => [previous_interval('year')],
                # Operators::PREVIOUS_X_DAYS_TO_DATE => [
                #   interval do |now, value|
                #     (now - value.days).beginning_of_day
                #     now
                #   end
                # ],
                # Operators::PREVIOUS_X_DAYS => [
                #   interval do |now, value|
                #     now.beginning_of_day - value.days
                #     now.beginning_of_day
                #   end
                # ],
                # Operators::TODAY => [
                #   interval do |now|
                #     now.beginning_of_day
                #     now.beginning_of_day + 1.day
                #   end
                # ]
                Operators::PREVIOUS_X_DAYS_TO_DATE => [
                  interval(
                    ->(now, value) { (now - value.days).beginning_of_day },
                    ->(now) { now }
                  )
                ],
                Operators::PREVIOUS_X_DAYS => [
                  interval(
                    ->(now, value) { (now - value.days).beginning_of_day },
                    ->(now) { now.beginning_of_day }
                  )
                ],
                Operators::TODAY => [
                  interval(
                    ->(now) { now.beginning_of_day },
                    ->(now) { (now + 1.day).beginning_of_day }
                  )
                ]
              }
            end
          end
        end
      end
    end
  end
end
