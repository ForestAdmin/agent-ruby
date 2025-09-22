module ForestAdminDatasourceToolkit
  module Components
    module Contracts
      class DatasourceContract
        def collections
          raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
        end

        def get_collection(name)
          raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
        end

        def add_collection(collection)
          raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
        end

        def render_chart(caller, name)
          raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
        end
      end
    end
  end
end
