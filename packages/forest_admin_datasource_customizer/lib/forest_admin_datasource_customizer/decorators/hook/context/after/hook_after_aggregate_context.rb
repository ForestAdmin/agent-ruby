module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      module Context
        module After
          class HookAfterAggregateContext < Hook::Context::Before::HookBeforeAggregateContext
            attr_reader :aggregate_result

            def initialize(collection, caller, filter, aggregation, aggregate_result, limit = nil)
              super(collection, caller, filter, aggregation, limit)
              @aggregate_result = aggregate_result
            end
          end
        end
      end
    end
  end
end
