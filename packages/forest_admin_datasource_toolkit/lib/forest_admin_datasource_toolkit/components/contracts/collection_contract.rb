module ForestAdminDatasourceToolkit
  module Components
    module Contracts
      class CollectionContract
        def datasource
          raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
        end

        def schema
          raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
        end

        def name
          raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
        end

        def execute
          raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
        end

        def form
          raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
        end

        def create(caller, data)
          raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
        end

        def list(caller, filter, projection)
          raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
        end

        def update
          raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
        end

        def delete
          raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
        end

        def aggregate(caller, filter, aggregation)
          raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
        end

        def render_chart
          raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
        end
      end
    end
  end
end
