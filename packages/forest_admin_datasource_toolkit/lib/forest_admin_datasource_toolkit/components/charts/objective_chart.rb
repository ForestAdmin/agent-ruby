module ForestAdminDatasourceToolkit
  module Components
    module Charts
      class ObjectiveChart
        attr_reader :value, :objective

        def initialize(value, objective = nil)
          super()
          @value = value
          @objective = objective
        end

        def serialize
          result = { value: value, objective: nil }
          result[:objective] = objective if objective

          result
        end
      end
    end
  end
end
