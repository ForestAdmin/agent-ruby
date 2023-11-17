module ForestAdminDatasourceToolkit
  module Components
    module Charts
      class LineChart
        include ForestAdminDatasourceToolkit::Validations

        attr_reader :data

        def initialize(data)
          super()
          @data = data
        end

        def serialize
          data.each do |item|
            ChartValidator.validate(!item.key?(:label) || !item.key?(:values), item, "'label', 'values'")
          end

          data
        end
      end
    end
  end
end
