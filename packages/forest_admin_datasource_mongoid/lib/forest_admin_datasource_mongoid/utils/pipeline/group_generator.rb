module ForestAdminDatasourceMongoid
  module Utils
    module Pipeline
      class GroupGenerator
        AGGREGATION_OPERATION = {
          'Sum' => '$sum',
          'Avg' => '$avg',
          'Count' => '$sum',
          'Max' => '$max',
          'Min' => '$min'
        }.freeze

        GROUP_OPERATION = {
          'Year' => '%Y-01-01',
          'Month' => '%Y-%m-01',
          'Day' => '%Y-%m-%d',
          'Week' => '%Y-%m-%d'
        }.freeze

        def self.group(aggregation)
          [
            {
              '$group' => {
                _id: compute_groups(aggregation.groups),
                value: compute_value(aggregation)
              }
            },
            {
              '$project' => {
                '_id' => 0,
                'value' => '$value',
                'group' => compute_groups_projection(aggregation.groups)
              }
            }
          ]
        end

        class << self
          private

          def compute_value(aggregation)
            # Handle count(*) case
            return { '$sum' => 1 } if aggregation.field.nil?

            # General case
            field = "$#{aggregation.field.tr(":", ".")}"

            if aggregation.operation == 'Count'
              { '$sum' => { '$cond' => [{ '$ne' => [field, nil] }, 1, 0] } }
            else
              { AGGREGATION_OPERATION[aggregation.operation] => field }
            end
          end

          def compute_groups(groups)
            return nil if groups.nil? || groups.empty?

            groups.reduce({}) do |memo, group|
              field = "$#{group[:field].tr(":", ".")}"

              if group[:operation]
                if group[:operation] == 'Week'
                  date = { '$dateTrunc' => { 'date' => field, 'startOfWeek' => 'Monday', 'unit' => 'week' } }
                  field = { '$dateToString' => { 'format' => GROUP_OPERATION[group[:operation]], 'date' => date } }
                else
                  field = { '$dateToString' => { 'format' => GROUP_OPERATION[group[:operation]], 'date' => field } }
                end
              end

              memo.merge(group[:field] => field)
            end
          end

          # Move fields in _id to the root of the document
          def compute_groups_projection(groups)
            return { '$literal' => {} } if groups.nil? || groups.empty?

            groups.each_with_object({}) do |group, memo|
              memo[group[:field]] = "$_id.#{group[:field]}"
            end
          end
        end
      end
    end
  end
end
