module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      module Context
        module Before
          class HookBeforeUpdateContext < Hook::Context::HookContext
            attr_reader :filter, :patch

            def initialize(collection, caller, filter, patch)
              super(collection, caller)
              @filter = filter
              @patch = patch
            end
          end
        end
      end
    end
  end
end
