module ForestAdminDatasourceToolkit
  module Components
    module Charts
      class Chart
        def serialize
          raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
        end
      end
    end
  end
end
