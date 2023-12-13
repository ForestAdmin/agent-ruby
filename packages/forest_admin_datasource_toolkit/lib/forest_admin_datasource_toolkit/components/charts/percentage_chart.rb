module ForestAdminDatasourceToolkit
  module Components
    module Charts
      class PercentageChart
        attr_reader :value

        def initialize(value)
          super()
          @value = value
        end

        def serialize
          value
        end
      end
    end
  end
end
