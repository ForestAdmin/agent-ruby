require 'active_support/all'
require 'active_support/core_ext/numeric/time'

module ForestAdminDatasourceToolkit
  module Components
    module Query
      class Aggregation
        include ForestAdminDatasourceToolkit::Exceptions
        attr_reader :operation
        attr_accessor :groups, :field

        def initialize(operation:, field: nil, groups: [])
          validate(operation)
          @operation = operation
          @field = field
          @groups = groups
        end

        def validate(operation)
          return if %w[Count Sum Avg Max Min].include? operation

          raise ForestException, "Aggregate operation #{operation} not allowed"
        end

        def projection
          aggregate_fields = []
          aggregate_fields << field.to_s if field

          groups.each do |group|
            aggregate_fields << group[:field].to_s
          end

          Projection.new(aggregate_fields)
        end

        def replace_fields
          result = clone
          result.field = yield(result.field) if result.field
          result.groups = result.groups.map do |group|
            {
              field: yield(group[:field]),
              operation: group[:operation] || nil
            }
          end
          result
        end

        def override(**args)
          Aggregation.new(**to_h, **args)
        end

        def apply(records, timezone, limit = nil)
          rows = format_summaries(create_summaries(records, timezone))
          rows.sort do |r1, r2|
            if r1[:value] == r2[:value]
              0
            else
              r1[:value] < r2[:value] ? 1 : -1
            end
          end

          rows = rows[0..limit - 1] if limit && rows.size > limit

          rows
        end

        def nest(prefix = nil)
          return self unless prefix

          nested_field = nil
          nested_groups = []
          nested_field = "#{prefix}:#{field}" if field

          if groups.size.positive?
            nested_groups = groups.map do |item|
              {
                field: "#{prefix}:#{item[:field]}",
                operation: item[:operation]
              }
            end
          end

          self.class.new(operation: operation, field: nested_field, groups: nested_groups)
        end

        def to_h
          {
            operation: operation,
            field: field,
            groups: groups
          }
        end

        private

        def create_summaries(records, timezone)
          grouping_map = {}

          records.each do |record|
            group = create_group(record, timezone)
            unique_key = Digest::SHA1.hexdigest(group.to_json)
            summary = grouping_map[unique_key] || create_summary(group)

            update_summary_in_place(summary, record)

            grouping_map[unique_key] = summary
          end

          grouping_map.values
        end

        def format_summaries(summaries)
          if operation == 'Avg'
            summaries
              .select { |summary| (summary['Count']).positive? }
              .map do |summary|
              {
                group: summary['group'],
                value: summary['Sum'] / summary['Count']
              }
            end
          else
            summaries.map do |summary|
              {
                group: summary['group'],
                value: operation == 'Count' && !field ? summary['starCount'] : summary[operation]
              }
            end
          end
        end

        def create_group(record, timezone)
          group = {}

          groups.each do |value|
            group_value = ForestAdminDatasourceToolkit::Utils::Record.field_value(record, value[:field])
            group[value[:field]] = apply_date_operation(group_value, value[:operation], timezone)
          end

          group
        end

        def apply_date_operation(value, operation, timezone)
          return value unless operation

          case operation
          when 'Year'
            DateTime.parse(value).in_time_zone(timezone).strftime('%Y-01-01')
          when 'Month'
            DateTime.parse(value).in_time_zone(timezone).strftime('%Y-%m-01')
          when 'Day'
            DateTime.parse(value).in_time_zone(timezone).strftime('%Y-%m-%d')
          when 'Week'
            DateTime.parse(value).in_time_zone(timezone).beginning_of_month.strftime('%Y-%m-%d')
          else
            value
          end
        end

        def create_summary(group)
          {
            'group' => group,
            'starCount' => 0,
            'Count' => 0,
            'Sum' => 0,
            'Min' => nil,
            'Max' => nil
          }
        end

        def update_summary_in_place(summary, record)
          summary['starCount'] += 1

          return unless field

          value = ForestAdminDatasourceToolkit::Utils::Record.field_value(record, field)

          if value
            min = summary['Min']
            max = summary['Max']

            summary['Count'] += 1
            summary['Min'] = value if min.nil? || value < min
            summary['Max'] = value if max.nil? || value < max
          end

          summary['Sum'] += value if value.is_a?(Numeric)
        end
      end
    end
  end
end
