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

            def _filter=(value)
              @filter = value
            end

            def _projection=(value)
              @projection = value
            end
          end
        end
      end
    end
  end
end
