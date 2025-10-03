module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      module Context
        module After
          class HookAfterListContext < Hook::Context::Before::HookBeforeListContext
            attr_reader :records

            def initialize(collection, caller, filter, projection, records)
              super(collection, caller, filter, projection)
              @records = records
            end

            def _records=(value)
              @records = value
            end
          end
        end
      end
    end
  end
end
