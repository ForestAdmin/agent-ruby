module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      module Context
        module Before
          class HookBeforeListContext < Hook::Context::HookContext
            attr_reader :filter, :projection

            def initialize(collection, caller, filter, projection)
              super(collection, caller)
              @filter = filter
              @projection = projection
            end
          end
        end
      end
    end
  end
end
