module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      module Context
        module Before
          class HookBeforeAggregateContext < Hook::Context::HookContext
            attr_reader :filter, :aggregation, :limit

            def initialize(collection, caller, filter, aggregation, limit = nil)
              super(collection, caller)
              @filter = filter
              @aggregation = aggregation
              @limit = limit
            end
          end
        end
      end
    end
  end
end
