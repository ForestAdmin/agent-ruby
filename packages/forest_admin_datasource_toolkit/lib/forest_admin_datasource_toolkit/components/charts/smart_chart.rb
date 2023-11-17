module ForestAdminDatasourceToolkit
  module Components
    module Charts
      class SmartChart
        attr_reader :data

        def initialize(data)
          super()
          @data = data
        end

        def serialize
          data
        end
      end
    end
  end
end
