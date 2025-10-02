module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      module Context
        module Before
          class HookBeforeDeleteContext < Hook::Context::HookContext
            attr_reader :filter

            def initialize(collection, caller, filter)
              super(collection, caller)
              @filter = filter
            end

            def _filter=(value)
              @filter = value
            end
          end
        end
      end
    end
  end
end
