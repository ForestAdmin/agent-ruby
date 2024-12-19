require 'active_support/all'
require 'active_support/core_ext/numeric/time'

module ForestAdminDatasourceToolkit
  module Components
    module Query
      module ConditionTree
        module Transforms
          class Times
            def self.format(value)
              value.in_time_zone('UTC').iso8601
            end

            def self.compare(operator)
              {
                depends_on: [operator],
                for_types: %w[Date Dateonly],
                replacer: proc { |leaf, tz|
                  leaf.override(operator: operator, value: format(yield(Time.now.in_time_zone(tz), leaf.value)))
                }
              }
            end

            def self.interval(start_fn, end_fn)
              {
                depends_on: [Operators::LESS_THAN, Operators::GREATER_THAN],
                for_types: %w[Date Dateonly],
                replacer: proc do |leaf, tz|
                  value_greater_than = if leaf.value.nil?
                                         format(start_fn.call(Time.now.in_time_zone(tz)))
                                       else
                                         format(start_fn.call(
                                                  Time.now.in_time_zone(tz), leaf.value
                                                ))
                                       end
                  value_less_than = if leaf.value.nil?
                                      format(end_fn.call(Time.now.in_time_zone(tz)))
                                    else
                                      format(end_fn.call(
                                               Time.now.in_time_zone(tz), leaf.value
                                             ))
                                    end

                  ConditionTreeFactory.intersect(
                    [
                      leaf.override(operator: Operators::GREATER_THAN, value: value_greater_than),
                      leaf.override(operator: Operators::LESS_THAN, value: value_less_than)
                    ]
                  )
                end
              }
            end

            def self.previous_interval(duration)
              interval(
                proc { |now|
                  if duration == 'quarter'
                    now.prev_quarter.send(:"beginning_of_#{duration}")
                  else
                    (now - 1.send(duration)).send(:"beginning_of_#{duration}")
                  end
                },
                proc { |now| now.send(:"beginning_of_#{duration}") }
              )
            end

            def self.previous_interval_to_date(duration)
              interval(
                proc { |now| now.send(:"beginning_of_#{duration}") },
                proc { |now| now }
              )
            end

            def self.transforms
              {
                Operators::BEFORE => [compare(Operators::LESS_THAN) { |_now, value| Time.parse(value.to_s) }],
                Operators::AFTER => [compare(Operators::GREATER_THAN) { |_now, value| Time.parse(value.to_s) }],
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
                Operators::PREVIOUS_X_DAYS_TO_DATE => [
                  interval(
                    proc { |now, value| (now - value.days).beginning_of_day },
                    proc { |now, _value| now }
                  )
                ],
                Operators::PREVIOUS_X_DAYS => [
                  interval(
                    proc { |now, value| (now - value.days).beginning_of_day },
                    proc { |now, _value| now.beginning_of_day }
                  )
                ],
                Operators::TODAY => [
                  interval(
                    proc(&:beginning_of_day),
                    proc { |now| (now + 1.day).beginning_of_day }
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
