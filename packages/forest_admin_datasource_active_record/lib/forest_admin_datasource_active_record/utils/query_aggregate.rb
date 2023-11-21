module ForestAdminDatasourceActiveRecord
  module Utils
    class QueryAggregate < Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      def initialize(collection, aggregation, filter = nil, limit = nil)
        super(collection, ForestAdminDatasourceToolkit::Components::Query::Projection.new, filter)
        @aggregation = aggregation
        @limit = limit
        @operation = aggregation.operation.downcase
        @field = aggregation.field.nil? ? '*' : format_field(aggregation.field)
      end

      def get
        @aggregation.groups.each do |group|
          field = format_field(group['field'])
          @select << field
        end

        @select << "#{@operation}(#{@field}) AS #{@operation}"
        @query.order("#{@operation} DESC")
        @query.limit(@limit) if @limit
        build

        compute_result_aggregate(@query)
      end

      def compute_result_aggregate(rows)
        rows.map do |row|
          {
            value: row.send(@operation.to_sym),
            group: @aggregation.groups.each_with_object({}) do |group, memo|
              memo[group['field']] = row.send(group['field'].to_sym)
            end
          }
        end
      end
    end
  end
end
