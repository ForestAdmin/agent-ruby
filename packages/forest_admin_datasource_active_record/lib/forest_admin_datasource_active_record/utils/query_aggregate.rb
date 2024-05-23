module ForestAdminDatasourceActiveRecord
  module Utils
    class QueryAggregate < Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Components::Query

      def initialize(collection, aggregation, filter = nil, limit = nil)
        super(collection, ForestAdminDatasourceToolkit::Components::Query::Projection.new, filter)
        @aggregation = aggregation
        @limit = limit
        @operation = aggregation.operation.downcase
        @field = aggregation.field.nil? ? '*' : format_field(aggregation.field)
      end

      def get
        group_fields = []
        @aggregation.groups.each do |group|
          field = format_field(group[:field])
          if group[:operation]
            @select << "DATE_TRUNC('#{group[:operation].downcase}', #{field}) AS \"#{group[:field]}\""
            group_fields << "DATE_TRUNC('#{group[:operation].downcase}', #{field})"
          else
            @select << "#{field} AS \"#{group[:field]}\""
            group_fields << field
          end
        end

        @select << "#{@operation}(#{@field}) AS #{@operation}"
        @query = @query.order("#{@operation} DESC")
        @query = @query.limit(@limit) if @limit
        @query = @query.group(group_fields.join(','))
        build

        compute_result_aggregate(@query)
      end

      def compute_result_aggregate(rows)
        rows.map do |row|
          {
            'value' => row.send(@operation.to_sym),
            'group' => @aggregation.groups.each_with_object({}) do |group, memo|
              memo[group[:field]] = row.send(group[:field].to_sym)
            end
          }
        end
      end
    end
  end
end
