module ForestAdminDatasourceMongoid
  module Utils
    class QueryAggregate < Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Components::Query

      GROUP_OPERATION = {
        'Year' => '%Y-01-01',
        'Month' => '%Y-%m-01',
        'Day' => '%Y-%m-%d',
        'Week' => '%Y-%m-%d'
      }.freeze

      def initialize(collection, aggregation, filter = nil, limit = nil)
        super(collection, ForestAdminDatasourceToolkit::Components::Query::Projection.new, filter)
        @aggregation = aggregation
        @limit = limit
        @operation = aggregation.operation.downcase
        @field = aggregation.field.nil? ? {} : format_field(aggregation.field)
      end

      def get
        build
        @query = @query.limit(@limit) if @limit
        @query = @query.group(_id: compute_groups, value: { "$#{@operation}" => @field })
                       .project(_id: 0, value: '$value', group: compute_groups_projection)

        @query.collection.aggregate(@query.pipeline).to_a
      end

      private

      def compute_groups
        @aggregation.groups.reduce({}) do |memo, group|
          field = "$#{format_field(group[:field])}"

          if group.key?(:operation)
            if group[:operation] == 'Week'
              date = { '$dateTrunc' => { 'date' => field, 'startOfWeek' => 'Monday', 'unit' => 'week' } }
              field = { '$dateToString' => { 'format' => GROUP_OPERATION[group[:operation]], 'date' => date } }
            else
              field = { '$dateToString' => { 'format' => GROUP_OPERATION[group[:operation]], 'date' => field } }
            end
          end

          memo.merge({ group[:field] => field })
        end
      end

      def compute_groups_projection
        if @aggregation.groups.length.positive?
          return @aggregation.groups
                             .reduce({}) { |memo, group| memo.merge({ group[:field] => "$_id.#{group[:field]}" }) }
        end

        { '$literal' => {} }
      end
    end
  end
end
