module ForestAdminDatasourceToolkit
  module Components
    module Charts
      class PieChart
        include ForestAdminDatasourceToolkit::Validations

        attr_reader :data

        def initialize(data)
          super()
          @data = data
        end

        def serialize
          data.each do |item|
            ChartValidator.validate(!item.key?(:key) || !item.key?(:value), item, "'key', 'value'")
          end

          data
        end
      end
    end
  end
end
