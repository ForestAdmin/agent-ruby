module ForestAdminDatasourceToolkit
  module Components
    module Charts
      class ValueChart
        attr_reader :value, :previous_value

        def initialize(value, previous_value = nil)
          super()
          @value = value
          @previous_value = previous_value
        end

        def serialize
          { countCurrent: value, countPrevious: previous_value }
        end
      end
    end
  end
end
