module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      module Context
        module Before
          class HookBeforeCreateContext < Hook::Context::HookContext
            attr_reader :data

            def initialize(collection, caller, data)
              super(collection, caller)
              @data = data
            end
          end
        end
      end
    end
  end
end
