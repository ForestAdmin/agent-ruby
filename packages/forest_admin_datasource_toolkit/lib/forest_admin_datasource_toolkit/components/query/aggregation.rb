module ForestAdminDatasourceToolkit
  module Components
    module Query
      class Aggregation
        include ForestAdminDatasourceToolkit::Exceptions
        attr_reader :operation, :field, :groups

        def initialize(operation:, field: nil, groups: [])
          validate(operation)
          @operation = operation
          @field = field
          @groups = groups
        end

        def validate(operation)
          return if %w[Count Sum Avg Max Min].include? operation

          raise ForestException.new("Aggregate operation #{operation} not allowed")
        end
      end
    end
  end
end
